#!/usr/bin/env python3
"""
Elasticsearch Restoration: Azure Blob Snapshot → New Cluster

Restores all indices to the new ES cluster from an existing Azure Blob Storage
snapshot via the repository-azure plugin.

Phases:
  1. Add Azure credentials to new ES keystore → reload secure settings
  2. Register repo on new ES → restore snapshot → wait for completion
  3. Verify restored data

Required env vars:
  AZURE_STORAGE_ACCOUNT_NAME   - Azure storage account name
  AZURE_STORAGE_ACCOUNT_KEY    - Azure storage account key
  AZURE_CONTAINER_NAME         - Azure blob container name (e.g. es-backups)
  AZURE_BASE_PATH              - Base path inside container (e.g. cluster-1)
  SNAPSHOT_NAME                - Name of the snapshot to restore (e.g. snapshot_1)
  REPOSITORY_NAME              - ES repository name (e.g. azure_backup)
  NEW_ES_URL                   - URL of new ES cluster (e.g. http://elasticsearch:9200)
  NEW_ES_POD_NAME              - Pod name of new ES (e.g. elasticsearch-master-0)
  NEW_ES_NAMESPACE             - Kubernetes namespace of new ES (e.g. sunbird)
  ES_KEYSTORE_PATH             - Full path to elasticsearch-keystore binary
"""

import json
import os
import subprocess
import sys
import time

# ========== CONFIGURATION ==========

AZURE_STORAGE_ACCOUNT_NAME = os.environ.get("AZURE_STORAGE_ACCOUNT_NAME")
AZURE_STORAGE_ACCOUNT_KEY  = os.environ.get("AZURE_STORAGE_ACCOUNT_KEY")
AZURE_CONTAINER_NAME       = os.environ.get("AZURE_CONTAINER_NAME")
AZURE_BASE_PATH            = os.environ.get("AZURE_BASE_PATH")
SNAPSHOT_NAME              = os.environ.get("SNAPSHOT_NAME")
REPOSITORY_NAME            = os.environ.get("REPOSITORY_NAME")
NEW_ES_URL                 = os.environ.get("NEW_ES_URL")
NEW_ES_POD_NAME            = os.environ.get("NEW_ES_POD_NAME")
NEW_ES_NAMESPACE           = os.environ.get("NEW_ES_NAMESPACE")
ES_KEYSTORE_PATH           = os.environ.get("ES_KEYSTORE_PATH")

RETRY_COUNT    = 3
RETRY_INTERVAL = 10   # seconds between retries
RESTORE_POLL   = 10   # seconds between restore health polls
RESTORE_TIMEOUT = 7200  # 2 hours max wait for restore


# ========== ENV VALIDATION ==========

def validate_env_vars():
    required = {
        "AZURE_STORAGE_ACCOUNT_NAME": AZURE_STORAGE_ACCOUNT_NAME,
        "AZURE_STORAGE_ACCOUNT_KEY":  AZURE_STORAGE_ACCOUNT_KEY,
        "AZURE_CONTAINER_NAME":       AZURE_CONTAINER_NAME,
        "AZURE_BASE_PATH":            AZURE_BASE_PATH,
        "SNAPSHOT_NAME":              SNAPSHOT_NAME,
        "REPOSITORY_NAME":            REPOSITORY_NAME,
        "NEW_ES_URL":                 NEW_ES_URL,
        "NEW_ES_POD_NAME":            NEW_ES_POD_NAME,
        "NEW_ES_NAMESPACE":           NEW_ES_NAMESPACE,
        "ES_KEYSTORE_PATH":           ES_KEYSTORE_PATH,
    }
    missing = [k for k, v in required.items() if not v]
    if missing:
        print("ERROR: Missing required environment variables:")
        for var in missing:
            print(f"  - {var}")
        sys.exit(1)
    print("  All required environment variables are set.")


# ========== HTTP HELPERS ==========

def curl_get(url, retries=RETRY_COUNT):
    """HTTP GET with retry. Returns (json_data, error). Uses -f so fails on 4xx/5xx."""
    for attempt in range(1, retries + 1):
        result = subprocess.run(
            ["curl", "-s", "-f", url],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            try:
                return json.loads(result.stdout), None
            except json.JSONDecodeError:
                return None, f"Invalid JSON: {result.stdout[:200]}"
        err = (result.stderr or result.stdout).strip()
        print(f"  GET attempt {attempt}/{retries} failed: {err}")
        if attempt < retries:
            time.sleep(RETRY_INTERVAL)
    return None, f"GET {url} failed after {retries} attempts"


def curl_get_raw(url, retries=RETRY_COUNT):
    """HTTP GET with retry. Returns (status_code, json_data, error).
    Does NOT use -f — allows callers to distinguish 404 from network errors."""
    for attempt in range(1, retries + 1):
        result = subprocess.run(
            ["curl", "-s", "-w", "\n%{http_code}", url],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            lines = result.stdout.rsplit("\n", 1)
            status = lines[-1].strip()
            body   = lines[0].strip() if len(lines) > 1 else ""
            try:
                return status, json.loads(body) if body else None, None
            except json.JSONDecodeError:
                return status, None, f"Invalid JSON: {body[:200]}"
        err = (result.stderr or result.stdout).strip()
        print(f"  GET attempt {attempt}/{retries} failed: {err}")
        if attempt < retries:
            time.sleep(RETRY_INTERVAL)
    return None, None, f"GET {url} failed after {retries} attempts"


def curl_put(url, data=None, retries=RETRY_COUNT):
    """HTTP PUT — returns (http_status_code, error). Prints response body on failure."""
    for attempt in range(1, retries + 1):
        cmd = ["curl", "-s", "-w", "\n%{http_code}", "-X", "PUT", url]
        if data is not None:
            cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(data)]
        result = subprocess.run(cmd, capture_output=True, text=True)
        # Last line is the status code, everything before is the body
        lines = result.stdout.strip().rsplit("\n", 1)
        status = lines[-1].strip() if len(lines) > 1 else result.stdout.strip()
        body   = lines[0].strip() if len(lines) > 1 else ""
        if status in ("200", "201"):
            return status, None
        print(f"  PUT attempt {attempt}/{retries}: HTTP {status}")
        if body:
            print(f"  Response: {body[:500]}")
        if attempt < retries:
            time.sleep(RETRY_INTERVAL)
    return status, f"PUT {url} failed after {retries} attempts"


def curl_post(url, data=None, retries=RETRY_COUNT):
    """HTTP POST — returns (json_data, error)."""
    for attempt in range(1, retries + 1):
        cmd = ["curl", "-s", "-X", "POST", url]
        if data is not None:
            cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(data)]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            try:
                return json.loads(result.stdout), None
            except json.JSONDecodeError:
                return None, f"Invalid JSON: {result.stdout[:200]}"
        err = (result.stderr or result.stdout).strip()
        print(f"  POST attempt {attempt}/{retries} failed: {err}")
        if attempt < retries:
            time.sleep(RETRY_INTERVAL)
    return None, f"POST {url} failed after {retries} attempts"


def curl_delete(url, retries=RETRY_COUNT):
    """HTTP DELETE — returns (http_status_code, error). 404 is treated as success (already gone)."""
    for attempt in range(1, retries + 1):
        cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-X", "DELETE", url]
        result = subprocess.run(cmd, capture_output=True, text=True)
        status = result.stdout.strip()
        if status in ("200", "201", "404"):
            return status, None
        err = result.stderr.strip()
        print(f"  DELETE attempt {attempt}/{retries}: HTTP {status} {err}")
        if attempt < retries:
            time.sleep(RETRY_INTERVAL)
    return status, f"DELETE {url} failed after {retries} attempts"


# ========== PHASE 1: NEW ES KEYSTORE ==========

def phase1_add_keystore_credentials():
    print("\n" + "=" * 60)
    print(" PHASE 1: Add Azure Credentials to New ES Keystore")
    print("=" * 60)
    print(f"  Pod: {NEW_ES_POD_NAME}  Namespace: {NEW_ES_NAMESPACE}")

    # Clean up any leftover .tmp files from a previous failed run
    keystore_dir = os.path.dirname(ES_KEYSTORE_PATH.rstrip('/'))
    config_dir = keystore_dir.replace("/bin", "/config")
    subprocess.run(
        ["kubectl", "exec", NEW_ES_POD_NAME, "-n", NEW_ES_NAMESPACE, "--",
         "bash", "-c", f"rm -f {config_dir}/elasticsearch.keystore.tmp"],
        capture_output=True, text=True,
    )

    # List existing keystore entries so we can skip keys that are already set
    list_cmd = [
        "kubectl", "exec", NEW_ES_POD_NAME, "-n", NEW_ES_NAMESPACE, "--",
        "bash", "-c", f"{ES_KEYSTORE_PATH} list",
    ]
    list_result = subprocess.run(list_cmd, capture_output=True, text=True)
    existing_keys = set(line.strip() for line in list_result.stdout.splitlines() if line.strip())
    print(f"  Existing keystore entries: {len(existing_keys)}")

    for key, value in [
        ("azure.client.default.account", AZURE_STORAGE_ACCOUNT_NAME),
        ("azure.client.default.key",     AZURE_STORAGE_ACCOUNT_KEY),
    ]:
        if key in existing_keys:
            print(f"  Keystore key '{key}' already present — skipping.")
            continue
        cmd = [
            "kubectl", "exec", NEW_ES_POD_NAME,
            "-n", NEW_ES_NAMESPACE, "--",
            "bash", "-c",
            f"echo '{value}' | {ES_KEYSTORE_PATH} add --stdin --force {key}",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  FAILED to add keystore key '{key}': {result.stderr.strip()}")
            sys.exit(1)
        print(f"  Added keystore key: {key}")

    # Reload secure settings so the plugin picks up the new credentials
    print("  Reloading secure settings on new ES...")
    data, err = curl_post(
        f"{NEW_ES_URL}/_nodes/reload_secure_settings",
        {"secure_settings_password": ""}
    )
    if err or (isinstance(data, dict) and "error" in data):
        print(f"  FAILED to reload secure settings: {err or data.get('error')}")
        sys.exit(1)
    print("  Secure settings reloaded successfully.")


# ========== PHASE 2: RESTORE TO NEW ES ==========

def register_repository(es_url, label, verify=True):
    """Register Azure snapshot repository. Exits if registration fails.

    verify=False skips the post-registration connectivity check ES performs.
    Useful when the cluster has outbound network restrictions to Azure Blob Storage,
    or when the container is known to exist but ES cannot reach it for verification.
    """
    # Unregister any existing repo first — ES may have cached stale state
    d_status, _ = curl_delete(f"{es_url}/_snapshot/{REPOSITORY_NAME}")
    print(f"  [{label}] Unregister (if exists) returned: HTTP {d_status}")

    verify_param = "" if verify else "?verify=false"
    print(f"  [{label}] Registering repository '{REPOSITORY_NAME}' (verify={verify})...")
    status, err = curl_put(
        f"{es_url}/_snapshot/{REPOSITORY_NAME}{verify_param}",
        {
            "type": "azure",
            "settings": {
                "container": AZURE_CONTAINER_NAME,
                "base_path": AZURE_BASE_PATH,
            },
        }
    )
    if status not in ("200", "201"):
        print(f"  [{label}] FAILED to register repository: HTTP {status} {err}")
        sys.exit(1)
    print(f"  [{label}] Repository '{REPOSITORY_NAME}' registered successfully.")


def phase2_restore():
    global SNAPSHOT_NAME
    print("\n" + "=" * 60)
    print(" PHASE 2: Restore Snapshot to New ES Cluster")
    print("=" * 60)

    # Register same Azure repository on new ES
    register_repository(NEW_ES_URL, "New ES")

    # Try the configured SNAPSHOT_NAME first; if not found, fall back to _all discovery
    print(f"\n  Looking up snapshot '{SNAPSHOT_NAME}' on new ES...")
    snap_visible = False
    for attempt in range(1, 4):
        s_status, s_data, _ = curl_get_raw(
            f"{NEW_ES_URL}/_snapshot/{REPOSITORY_NAME}/{SNAPSHOT_NAME}"
        )
        if s_status == "200" and s_data and s_data.get("snapshots"):
            snap = s_data["snapshots"][0]
            print(f"  Snapshot '{SNAPSHOT_NAME}' found: state={snap.get('state')}  indices={len(snap.get('indices', []))}")
            snap_visible = True
            break
        print(f"  Not found yet (attempt {attempt}/3) — re-registering repository to refresh Azure index...")
        register_repository(NEW_ES_URL, "New ES", verify=False)
        time.sleep(5)

    # Fallback: list all snapshots in the repo and pick the latest
    if not snap_visible:
        print(f"\n  '{SNAPSHOT_NAME}' not found — discovering available snapshots in repository...")
        all_status, all_data, _ = curl_get_raw(f"{NEW_ES_URL}/_snapshot/{REPOSITORY_NAME}/_all")
        snapshots = (all_data or {}).get("snapshots", []) if all_status == "200" else []
        if not snapshots:
            print(f"  FAILED: No snapshots found in repository '{REPOSITORY_NAME}'.")
            print(f"  Check container '{AZURE_CONTAINER_NAME}' at base_path '{AZURE_BASE_PATH}'.")
            sys.exit(1)
        print(f"  Found {len(snapshots)} snapshot(s) in repository:")
        for s in snapshots:
            print(f"    - {s.get('snapshot')}  state={s.get('state')}  start={s.get('start_time')}")
        # Pick the latest by start_time_in_millis (fall back to last in list)
        latest = max(snapshots, key=lambda s: s.get("start_time_in_millis", 0))
        SNAPSHOT_NAME = latest.get("snapshot")
        print(f"  Using latest snapshot: '{SNAPSHOT_NAME}'")

    # Delete any existing non-system indices to avoid conflicts
    print(f"\n  Checking for existing indices on new ES...")
    data, err = curl_get(f"{NEW_ES_URL}/_cat/indices?format=json&h=index")
    existing = [
        item["index"] for item in (data or [])
        if not item["index"].startswith(".")
    ]
    if existing:
        print(f"  Found {len(existing)} existing index/indices — deleting before restore:")
        for idx in existing:
            print(f"    - {idx}")
        status, err = curl_delete(f"{NEW_ES_URL}/_all")
        if status not in ("200", "201"):
            print(f"  FAILED to delete existing indices: HTTP {status} {err}")
            sys.exit(1)
        print(f"  All existing indices deleted.")
    else:
        print(f"  No existing indices — proceeding with restore.")

    # Initiate restore
    print(f"\n  Restoring snapshot '{SNAPSHOT_NAME}'...")
    data, err = curl_post(
        f"{NEW_ES_URL}/_snapshot/{REPOSITORY_NAME}/{SNAPSHOT_NAME}/_restore"
    )
    if err:
        print(f"  FAILED to initiate restore: {err}")
        sys.exit(1)
    if isinstance(data, dict) and "error" in data:
        print(f"  FAILED to initiate restore: {data['error']}")
        sys.exit(1)
    print(f"  Restore initiated.")

    # Poll cluster health until stable
    print(f"  Waiting for restore to complete (polling every {RESTORE_POLL}s)...")
    elapsed = 0
    while elapsed < RESTORE_TIMEOUT:
        time.sleep(RESTORE_POLL)
        elapsed += RESTORE_POLL

        health, err = curl_get(f"{NEW_ES_URL}/_cluster/health")
        if err or health is None:
            print(f"  [{elapsed}s] Could not reach new ES — retrying...")
            continue

        status           = health.get("status", "unknown")
        initializing     = health.get("initializing_shards", -1)
        relocating       = health.get("relocating_shards", -1)
        active_primary   = health.get("active_primary_shards", 0)
        unassigned       = health.get("unassigned_shards", 0)

        print(f"  [{elapsed}s] status={status}  initializing={initializing}"
              f"  relocating={relocating}  active_primary={active_primary}"
              f"  unassigned={unassigned}")

        if initializing == 0 and relocating == 0:
            print(f"\n  Restore complete — cluster is stable.")
            return

    print(f"  FAILED: Restore did not complete within {RESTORE_TIMEOUT // 60} minutes.")
    sys.exit(1)


# ========== PHASE 3: VERIFY ==========

def phase3_verify():
    print("\n" + "=" * 60)
    print(" PHASE 3: Verification")
    print("=" * 60)

    data, err = curl_get(
        f"{NEW_ES_URL}/_cat/indices?format=json&h=index,docs.count,status,health"
    )
    if err or data is None:
        print(f"  FAILED to get indices from new ES: {err}")
        sys.exit(1)

    new_indices = {
        item["index"]: int(item.get("docs.count") or 0)
        for item in data
        if not item["index"].startswith(".")
    }
    new_health_map = {
        item["index"]: item.get("health", "unknown")
        for item in data
        if not item["index"].startswith(".")
    }

    count_data, _ = curl_get(f"{NEW_ES_URL}/_cat/count?format=json")
    new_total = int(count_data[0].get("count", 0)) if count_data else None

    checks_passed = True

    print(f"  Restored indices: {len(new_indices)}")
    print(f"  Total documents:  {new_total if new_total is not None else 'unknown'}")

    # Check: No RED health indices (yellow is expected on single-node)
    red_indices = [idx for idx, h in new_health_map.items() if h == "red"]
    if red_indices:
        print(f"  [FAIL] RED health indices ({len(red_indices)}):")
        for idx in red_indices:
            print(f"    - {idx}")
        checks_passed = False
    else:
        print(f"  [PASS] No RED health indices (yellow is normal on single-node)")

    # Check: All restored indices are open
    all_data, _ = curl_get(f"{NEW_ES_URL}/_cat/indices?format=json&h=index,status")
    if all_data:
        closed = [item["index"] for item in all_data if item.get("status") == "close"]
        if closed:
            print(f"  [FAIL] Closed indices ({len(closed)}):")
            for idx in closed:
                print(f"    - {idx}")
            checks_passed = False
        else:
            print(f"  [PASS] All indices are open")

    return checks_passed


# ========== MAIN ==========

def main():
    print("=" * 60)
    print(" Elasticsearch Restoration: Azure Blob Snapshot → New Cluster")
    print("=" * 60)
    print(f"  NEW_ES_URL:           {NEW_ES_URL}")
    print(f"  AZURE_CONTAINER_NAME: {AZURE_CONTAINER_NAME}")
    print(f"  AZURE_BASE_PATH:      {AZURE_BASE_PATH}")
    print(f"  REPOSITORY_NAME:      {REPOSITORY_NAME}")
    print(f"  SNAPSHOT_NAME:        {SNAPSHOT_NAME}")
    print(f"  NEW_ES_POD:           {NEW_ES_POD_NAME} (ns: {NEW_ES_NAMESPACE})")
    print("=" * 60)

    validate_env_vars()
    phase1_add_keystore_credentials()
    phase2_restore()
    passed = phase3_verify()

    print("\n" + "=" * 60)
    if passed:
        print(" RESTORATION COMPLETE — All verification checks passed!")
        print("=" * 60)
        sys.exit(0)
    else:
        print(" RESTORATION FAILED — One or more verification checks failed!")
        print("=" * 60)
        sys.exit(1)


if __name__ == "__main__":
    main()
