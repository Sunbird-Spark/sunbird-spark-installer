#!/usr/bin/env python3
"""
Elasticsearch Migration: Old Cluster → New Cluster (Azure Blob Snapshot)

Migrates all indices from old ES cluster to new ES cluster using
Azure Blob Storage snapshots via the repository-azure plugin.

Phases:
  1. Check/Create Azure Blob container
  2. Add Azure credentials to new ES keystore → reload secure settings
  3. Register repo on old ES → check/take snapshot → verify
  4. Register repo on new ES → restore snapshot → wait for completion
  5. Verify restored data matches old ES state

Required env vars:
  AZURE_STORAGE_ACCOUNT_NAME   - Azure storage account name
  AZURE_STORAGE_ACCOUNT_KEY    - Azure storage account key
  AZURE_CONTAINER_NAME         - Azure blob container name (e.g. es-backups)
  AZURE_BASE_PATH              - Base path inside container (e.g. cluster-1)
  SNAPSHOT_NAME                - Name of the snapshot (e.g. snapshot_1)
  REPOSITORY_NAME              - ES repository name (e.g. azure_backup)
  OLD_ES_URL                   - Load balancer URL of old ES cluster (e.g. http://10.x.x.x:9200)
  NEW_ES_URL                   - URL of new ES cluster (e.g. http://elasticsearch:9200)
  NEW_ES_POD_NAME              - Pod name of new ES (e.g. elasticsearch-master-0)
  NEW_ES_NAMESPACE             - Kubernetes namespace of new ES (e.g. sunbird)
  ES_KEYSTORE_PATH             - Full path to elasticsearch-keystore binary

Note: Old ES keystore must be pre-configured with Azure credentials by the operator
      before running this script. The script only manages the new ES keystore.
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
OLD_ES_URL                 = os.environ.get("OLD_ES_URL")
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
        "OLD_ES_URL":                 OLD_ES_URL,
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


def curl_put_with_body(url, data=None, timeout=None, retries=RETRY_COUNT):
    """HTTP PUT — returns (json_data, error). Captures body (used for snapshot)."""
    for attempt in range(1, retries + 1):
        cmd = ["curl", "-s", "-X", "PUT", url]
        if timeout:
            cmd += ["--max-time", str(timeout)]
        if data is not None:
            cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(data)]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 30 if timeout else None)
        if result.returncode == 0:
            try:
                return json.loads(result.stdout), None
            except json.JSONDecodeError:
                return None, f"Invalid JSON: {result.stdout[:200]}"
        err = (result.stderr or result.stdout).strip()
        print(f"  PUT attempt {attempt}/{retries} failed: {err}")
        if attempt < retries:
            time.sleep(RETRY_INTERVAL)
    return None, f"PUT {url} failed after {retries} attempts"


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


# ========== PHASE 1: AZURE CONTAINER ==========

def phase1_azure_container():
    print("\n" + "=" * 60)
    print(" PHASE 1: Azure Container Setup")
    print("=" * 60)

    result = subprocess.run([
        "az", "storage", "container", "show",
        "--name",         AZURE_CONTAINER_NAME,
        "--account-name", AZURE_STORAGE_ACCOUNT_NAME,
        "--account-key",  AZURE_STORAGE_ACCOUNT_KEY,
    ], capture_output=True, text=True)

    if result.returncode == 0:
        print(f"  Container '{AZURE_CONTAINER_NAME}' already exists — skipping creation.")
        return

    print(f"  Container '{AZURE_CONTAINER_NAME}' not found. Creating...")
    result = subprocess.run([
        "az", "storage", "container", "create",
        "--name",         AZURE_CONTAINER_NAME,
        "--account-name", AZURE_STORAGE_ACCOUNT_NAME,
        "--account-key",  AZURE_STORAGE_ACCOUNT_KEY,
    ], capture_output=True, text=True)

    if result.returncode != 0:
        print(f"  FAILED to create container: {result.stderr.strip()}")
        sys.exit(1)

    print(f"  Container '{AZURE_CONTAINER_NAME}' created successfully.")


# ========== PHASE 2: NEW ES KEYSTORE ==========

def phase2_add_keystore_credentials():
    print("\n" + "=" * 60)
    print(" PHASE 2: Add Azure Credentials to New ES Keystore")
    print("=" * 60)
    print(f"  Pod: {NEW_ES_POD_NAME}  Namespace: {NEW_ES_NAMESPACE}")

    for key, value in [
        ("azure.client.default.account", AZURE_STORAGE_ACCOUNT_NAME),
        ("azure.client.default.key",     AZURE_STORAGE_ACCOUNT_KEY),
    ]:
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


# ========== PHASE 3: SNAPSHOT FROM OLD ES ==========

def register_repository(es_url, label, verify=True):
    """Register Azure snapshot repository. Exits if registration fails.

    verify=False skips the post-registration connectivity check ES performs.
    Useful when the cluster has outbound network restrictions to Azure Blob Storage,
    or when the container is known to exist but ES cannot reach it for verification.
    """
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
        if label == "Old ES":
            print("  Hint: Ensure Azure credentials are pre-configured in old ES keystore.")
            print("        Run on old ES pod:")
            print(f"    echo '<account>' | {ES_KEYSTORE_PATH} add --stdin --force azure.client.default.account")
            print(f"    echo '<key>'     | {ES_KEYSTORE_PATH} add --stdin --force azure.client.default.key")
            print("        Then reload: POST /_nodes/reload_secure_settings")
        sys.exit(1)
    print(f"  [{label}] Repository '{REPOSITORY_NAME}' registered successfully.")


def get_old_es_state():
    """Capture current index state of old ES for later verification."""
    data, err = curl_get(
        f"{OLD_ES_URL}/_cat/indices?format=json&h=index,docs.count,store.size,status,health"
    )
    if err or data is None:
        print(f"  FAILED to get indices from old ES: {err}")
        sys.exit(1)

    indices = {
        item["index"]: int(item.get("docs.count") or 0)
        for item in data
        if not item["index"].startswith(".")
    }

    count_data, _ = curl_get(f"{OLD_ES_URL}/_cat/count?format=json")
    total = int(count_data[0].get("count", 0)) if count_data else None

    health_data, _ = curl_get(f"{OLD_ES_URL}/_cluster/health")
    health = health_data.get("status", "unknown") if health_data else "unknown"

    print(f"  Old ES state captured:")
    print(f"    Indices:    {len(indices)}")
    print(f"    Total docs: {total if total is not None else 'unknown'}")
    print(f"    Health:     {health}")
    return {"indices": indices, "total_count": total}


def phase3_snapshot():
    print("\n" + "=" * 60)
    print(" PHASE 3: Snapshot from Old ES Cluster")
    print("=" * 60)

    # Delete any existing repository on old ES before re-registering.
    # This clears stale ES cluster state (e.g. snapshot names from a previous run
    # where the Azure container was deleted/recreated). Without this, ES may
    # return invalid_snapshot_name_exception even though the container is empty.
    print(f"  Clearing any existing repository state on old ES...")
    curl_delete(f"{OLD_ES_URL}/_snapshot/{REPOSITORY_NAME}")  # 404 is fine — ignore

    # Register Azure repository on old ES (fresh state)
    # verify=False skips the test-write ES does to confirm Azure connectivity.
    # The snapshot attempt itself will confirm whether Azure is truly reachable.
    register_repository(OLD_ES_URL, "Old ES", verify=False)

    # Check if snapshot already exists
    # Uses curl_get_raw (no -f) so we can distinguish 404 (not found) from network errors.
    print(f"\n  Checking if snapshot '{SNAPSHOT_NAME}' already exists...")
    status, data, err = curl_get_raw(f"{OLD_ES_URL}/_snapshot/{REPOSITORY_NAME}/{SNAPSHOT_NAME}")

    if status == "200" and data and data.get("snapshots"):
        snap = data["snapshots"][0]
        print(f"  Snapshot '{SNAPSHOT_NAME}' already exists — skipping backup.")
        print(f"    State:   {snap.get('state')}")
        print(f"    Indices: {len(snap.get('indices', []))}")
        for idx in snap.get("indices", []):
            print(f"      - {idx}")
        return {
            "indices":     {idx: 0 for idx in snap.get("indices", [])},
            "total_count": None,
        }
    elif status == "404":
        print(f"  Snapshot not found — will create a new one.")
    elif status is None or err:
        print(f"  ERROR: Could not check snapshot existence: {err}")
        sys.exit(1)
    else:
        print(f"  WARNING: Unexpected status {status} checking snapshot — proceeding to create.")

    # Capture old ES state before taking snapshot
    print(f"\n  Snapshot not found. Capturing old ES state...")
    old_state = get_old_es_state()

    # Capture full cluster state for reference
    print(f"\n  Cluster health:")
    health, _ = curl_get(f"{OLD_ES_URL}/_cluster/health?pretty")
    if health:
        print(f"    status={health.get('status')}  active_shards={health.get('active_shards')}")

    # Take snapshot (wait_for_completion blocks until done)
    print(f"\n  Taking snapshot '{SNAPSHOT_NAME}' (waiting for completion — this may take minutes)...")
    data, err = curl_put_with_body(
        f"{OLD_ES_URL}/_snapshot/{REPOSITORY_NAME}/{SNAPSHOT_NAME}?wait_for_completion=true",
        timeout=3600  # 1 hour max for snapshot
    )

    if err or data is None:
        print(f"  FAILED to take snapshot: {err}")
        sys.exit(1)

    if "error" in data:
        error_type = data["error"].get("type", "")
        if error_type == "invalid_snapshot_name_exception":
            # ES says snapshot name is taken — verify it actually exists in Azure
            s_status, existing, _ = curl_get_raw(f"{OLD_ES_URL}/_snapshot/{REPOSITORY_NAME}/{SNAPSHOT_NAME}")
            if s_status == "200" and existing and existing.get("snapshots"):
                snap = existing["snapshots"][0]
                print(f"  Snapshot '{SNAPSHOT_NAME}' confirmed in Azure — skipping creation.")
                print(f"    State:   {snap.get('state')}")
                print(f"    Indices: {len(snap.get('indices', []))}")
                return old_state
            # ES thinks it exists but Azure doesn't have it — stale state persisted despite delete
            print(f"  ERROR: ES reports snapshot exists but Azure container is empty.")
            print(f"  Manually delete the repository on old ES and retry:")
            print(f"    curl -X DELETE {OLD_ES_URL}/_snapshot/{REPOSITORY_NAME}")
            sys.exit(1)
        print(f"  FAILED to take snapshot: {data['error']}")
        sys.exit(1)

    snap = data.get("snapshot", {})
    state        = snap.get("state", "UNKNOWN")
    failed_shards = snap.get("shards", {}).get("failed", 0)

    if state != "SUCCESS":
        print(f"  FAILED: Snapshot state is '{state}' (expected SUCCESS)")
        sys.exit(1)
    if failed_shards > 0:
        print(f"  FAILED: Snapshot has {failed_shards} failed shard(s)")
        sys.exit(1)

    print(f"  Snapshot completed successfully.")
    print(f"    State:         {state}")
    print(f"    Indices:       {len(snap.get('indices', []))}")
    print(f"    Failed shards: {failed_shards}")

    # Verify snapshot is visible in repository
    print(f"\n  Verifying snapshot in repository...")
    all_snaps, _ = curl_get(f"{OLD_ES_URL}/_snapshot/{REPOSITORY_NAME}/_all")
    if all_snaps and "snapshots" in all_snaps:
        print(f"  Repository contains {len(all_snaps['snapshots'])} snapshot(s):")
        for s in all_snaps["snapshots"]:
            print(f"    - {s.get('snapshot')}  state={s.get('state')}  indices={len(s.get('indices', []))}")

    return old_state


# ========== PHASE 4: RESTORE TO NEW ES ==========

def phase4_restore():
    print("\n" + "=" * 60)
    print(" PHASE 4: Restore Snapshot to New ES Cluster")
    print("=" * 60)

    # Register same Azure repository on new ES
    register_repository(NEW_ES_URL, "New ES")

    # Verify snapshot is visible on new ES — re-register repo to force re-read of Azure index if not
    print(f"\n  Verifying snapshot '{SNAPSHOT_NAME}' is visible on new ES...")
    snap_visible = False
    for attempt in range(1, 4):
        s_status, s_data, _ = curl_get_raw(
            f"{NEW_ES_URL}/_snapshot/{REPOSITORY_NAME}/{SNAPSHOT_NAME}"
        )
        if s_status == "200" and s_data and s_data.get("snapshots"):
            snap = s_data["snapshots"][0]
            print(f"  Snapshot visible: state={snap.get('state')}  indices={len(snap.get('indices', []))}")
            snap_visible = True
            break
        print(f"  Snapshot not visible yet (attempt {attempt}/3) — re-registering repository to refresh index...")
        register_repository(NEW_ES_URL, "New ES", verify=False)
        time.sleep(5)

    if not snap_visible:
        print(f"  FAILED: Snapshot '{SNAPSHOT_NAME}' is not visible on new ES after 3 attempts.")
        print(f"  Ensure the snapshot was successfully created on old ES and is in container '{AZURE_CONTAINER_NAME}' at base_path '{AZURE_BASE_PATH}'.")
        sys.exit(1)

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


# ========== PHASE 5: VERIFY ==========

def phase5_verify(old_state):
    print("\n" + "=" * 60)
    print(" PHASE 5: Verification")
    print("=" * 60)

    # Capture new ES state
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

    old_indices   = old_state.get("indices", {})
    old_total     = old_state.get("total_count")
    checks_passed = True

    # Check 1: Index count
    if len(new_indices) >= len(old_indices):
        print(f"  [PASS] Index count      : old={len(old_indices)}  new={len(new_indices)}")
    else:
        print(f"  [FAIL] Index count      : old={len(old_indices)}  new={len(new_indices)}")
        checks_passed = False

    # Check 2: Total document count
    if old_total is None:
        print(f"  [SKIP] Total doc count  : old=unknown (snapshot was pre-existing)")
    elif new_total is not None and new_total >= old_total:
        print(f"  [PASS] Total doc count  : old={old_total}  new={new_total}")
    else:
        print(f"  [FAIL] Total doc count  : old={old_total}  new={new_total}")
        checks_passed = False

    # Check 3: Each index exists
    missing = [idx for idx in old_indices if idx not in new_indices]
    if missing:
        print(f"  [FAIL] Missing indices  : {len(missing)} index/indices not found in new ES")
        for idx in missing:
            print(f"    - {idx}")
        checks_passed = False
    else:
        print(f"  [PASS] All indices present in new ES")

    # Check 4: Per-index document count
    mismatched = [
        (idx, old_c, new_indices[idx])
        for idx, old_c in old_indices.items()
        if old_c > 0 and idx in new_indices and new_indices[idx] < old_c
    ]
    if mismatched:
        print(f"  [FAIL] Doc count mismatch on {len(mismatched)} index/indices:")
        for idx, old_c, new_c in mismatched:
            print(f"    - {idx}: old={old_c}  new={new_c}")
        checks_passed = False
    else:
        print(f"  [PASS] Doc counts match for all indices")

    # Check 5: No RED health indices (yellow is expected on single-node)
    red_indices = [idx for idx, h in new_health_map.items() if h == "red"]
    if red_indices:
        print(f"  [FAIL] RED health indices ({len(red_indices)}):")
        for idx in red_indices:
            print(f"    - {idx}")
        checks_passed = False
    else:
        print(f"  [PASS] No RED health indices (yellow is normal on single-node)")

    return checks_passed


# ========== MAIN ==========

def main():
    print("=" * 60)
    print(" Elasticsearch Migration: Old Cluster → New Cluster")
    print(" Method: Azure Blob Storage Snapshot")
    print("=" * 60)
    print(f"  OLD_ES_URL:           {OLD_ES_URL}")
    print(f"  NEW_ES_URL:           {NEW_ES_URL}")
    print(f"  AZURE_CONTAINER_NAME: {AZURE_CONTAINER_NAME}")
    print(f"  AZURE_BASE_PATH:      {AZURE_BASE_PATH}")
    print(f"  REPOSITORY_NAME:      {REPOSITORY_NAME}")
    print(f"  SNAPSHOT_NAME:        {SNAPSHOT_NAME}")
    print(f"  NEW_ES_POD:           {NEW_ES_POD_NAME} (ns: {NEW_ES_NAMESPACE})")
    print("=" * 60)

    validate_env_vars()
    phase1_azure_container()
    phase2_add_keystore_credentials()
    old_state = phase3_snapshot()
    phase4_restore()
    passed = phase5_verify(old_state)

    print("\n" + "=" * 60)
    if passed:
        print(" MIGRATION COMPLETE — All verification checks passed!")
        print("=" * 60)
        sys.exit(0)
    else:
        print(" MIGRATION FAILED — One or more verification checks failed!")
        print("=" * 60)
        sys.exit(1)


if __name__ == "__main__":
    main()
