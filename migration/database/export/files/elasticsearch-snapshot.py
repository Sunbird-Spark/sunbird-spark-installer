#!/usr/bin/env python3
"""
Elasticsearch Snapshot → Azure Blob Storage

Creates a snapshot of all indices on the source ES cluster and stores it in
Azure Blob Storage via the repository-azure plugin.

Phases:
  1. Add Azure credentials to source ES keystore → reload secure settings
  2. Register repo → delete prior snapshot (for clean re-run) → create new snapshot
  3. Verify snapshot state & upload metadata summary

Required env vars:
  AZURE_STORAGE_ACCOUNT_NAME   - Azure storage account name
  AZURE_STORAGE_ACCOUNT_KEY    - Azure storage account key
  AZURE_CONTAINER_NAME         - Azure blob container name
  AZURE_BASE_PATH              - Base path inside container
  SNAPSHOT_NAME                - Name to give the snapshot
  REPOSITORY_NAME              - ES repository name
  SOURCE_ES_URL                - URL of source ES cluster
  SOURCE_ES_POD_NAME           - Pod name of source ES
  SOURCE_ES_NAMESPACE          - Kubernetes namespace of source ES
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
SOURCE_ES_URL              = os.environ.get("SOURCE_ES_URL")
SOURCE_ES_POD_NAME         = os.environ.get("SOURCE_ES_POD_NAME")
SOURCE_ES_NAMESPACE        = os.environ.get("SOURCE_ES_NAMESPACE")
ES_KEYSTORE_PATH           = os.environ.get("ES_KEYSTORE_PATH")

RETRY_COUNT      = 3
RETRY_INTERVAL   = 10
SNAPSHOT_POLL    = 10
SNAPSHOT_TIMEOUT = 7200  # 2 hours


# ========== ENV VALIDATION ==========

def validate_env_vars():
    required = {
        "AZURE_STORAGE_ACCOUNT_NAME": AZURE_STORAGE_ACCOUNT_NAME,
        "AZURE_STORAGE_ACCOUNT_KEY":  AZURE_STORAGE_ACCOUNT_KEY,
        "AZURE_CONTAINER_NAME":       AZURE_CONTAINER_NAME,
        "AZURE_BASE_PATH":            AZURE_BASE_PATH,
        "SNAPSHOT_NAME":              SNAPSHOT_NAME,
        "REPOSITORY_NAME":            REPOSITORY_NAME,
        "SOURCE_ES_URL":              SOURCE_ES_URL,
        "SOURCE_ES_POD_NAME":         SOURCE_ES_POD_NAME,
        "SOURCE_ES_NAMESPACE":        SOURCE_ES_NAMESPACE,
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
        if attempt < retries:
            time.sleep(RETRY_INTERVAL)
    return None, None, f"GET {url} failed after {retries} attempts"


def curl_put(url, data=None, retries=RETRY_COUNT):
    for attempt in range(1, retries + 1):
        cmd = ["curl", "-s", "-w", "\n%{http_code}", "-X", "PUT", url]
        if data is not None:
            cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(data)]
        result = subprocess.run(cmd, capture_output=True, text=True)
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
        if attempt < retries:
            time.sleep(RETRY_INTERVAL)
    return None, f"POST {url} failed after {retries} attempts"


def curl_delete(url, retries=RETRY_COUNT):
    for attempt in range(1, retries + 1):
        cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-X", "DELETE", url]
        result = subprocess.run(cmd, capture_output=True, text=True)
        status = result.stdout.strip()
        if status in ("200", "201", "404"):
            return status, None
        if attempt < retries:
            time.sleep(RETRY_INTERVAL)
    return status, f"DELETE {url} failed after {retries} attempts"


# ========== PHASE 1: SOURCE ES KEYSTORE ==========

def phase1_add_keystore_credentials():
    print("\n" + "=" * 60)
    print(" PHASE 1: Add Azure Credentials to Source ES Keystore")
    print("=" * 60)
    print(f"  Pod: {SOURCE_ES_POD_NAME}  Namespace: {SOURCE_ES_NAMESPACE}")

    # Clean up any leftover .tmp files from a previous failed run
    keystore_dir = os.path.dirname(ES_KEYSTORE_PATH.rstrip('/'))
    config_dir = keystore_dir.replace("/bin", "/config")
    subprocess.run(
        ["kubectl", "exec", SOURCE_ES_POD_NAME, "-n", SOURCE_ES_NAMESPACE, "--",
         "bash", "-c", f"rm -f {config_dir}/elasticsearch.keystore.tmp"],
        capture_output=True, text=True,
    )

    # List existing keystore entries so we can skip keys that are already set
    list_cmd = [
        "kubectl", "exec", SOURCE_ES_POD_NAME, "-n", SOURCE_ES_NAMESPACE, "--",
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
            "kubectl", "exec", SOURCE_ES_POD_NAME,
            "-n", SOURCE_ES_NAMESPACE, "--",
            "bash", "-c",
            f"echo '{value}' | {ES_KEYSTORE_PATH} add --stdin --force {key}",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"  FAILED to add keystore key '{key}': {result.stderr.strip()}")
            sys.exit(1)
        print(f"  Added keystore key: {key}")

    print("  Reloading secure settings on source ES...")
    data, err = curl_post(
        f"{SOURCE_ES_URL}/_nodes/reload_secure_settings",
        {"secure_settings_password": ""}
    )
    if err or (isinstance(data, dict) and "error" in data):
        print(f"  FAILED to reload secure settings: {err or data.get('error')}")
        sys.exit(1)
    print("  Secure settings reloaded successfully.")


# ========== PHASE 2: CREATE SNAPSHOT ==========

def register_repository():
    # Unregister any existing repo first — ES may have cached stale state from
    # a previous failed run, which causes "repository data do not match expected state"
    # errors on subsequent writes even if the blob path is empty.
    print(f"\n  Unregistering any existing repo '{REPOSITORY_NAME}' (ok if 404)...")
    d_status, _ = curl_delete(f"{SOURCE_ES_URL}/_snapshot/{REPOSITORY_NAME}")
    print(f"  Unregister returned: HTTP {d_status}")

    print(f"  Registering repository '{REPOSITORY_NAME}'...")
    status, err = curl_put(
        f"{SOURCE_ES_URL}/_snapshot/{REPOSITORY_NAME}",
        {
            "type": "azure",
            "settings": {
                "client": "default",
                "container": AZURE_CONTAINER_NAME,
                "base_path": AZURE_BASE_PATH,
                "compress": True,
            },
        }
    )
    if status not in ("200", "201"):
        print(f"  FAILED to register repository: HTTP {status} {err}")
        sys.exit(1)
    print(f"  Repository '{REPOSITORY_NAME}' registered successfully.")


def phase2_create_snapshot():
    print("\n" + "=" * 60)
    print(" PHASE 2: Create Snapshot on Source ES Cluster")
    print("=" * 60)

    register_repository()

    # Delete existing snapshot with the same name (allows clean re-run)
    print(f"\n  Deleting any existing snapshot '{SNAPSHOT_NAME}' (ok if 404)...")
    status, _ = curl_delete(f"{SOURCE_ES_URL}/_snapshot/{REPOSITORY_NAME}/{SNAPSHOT_NAME}")
    print(f"  Delete returned: HTTP {status}")

    # Create snapshot (wait_for_completion=true blocks until done)
    print(f"\n  Creating snapshot '{SNAPSHOT_NAME}' (wait_for_completion=true)...")
    status, err = curl_put(
        f"{SOURCE_ES_URL}/_snapshot/{REPOSITORY_NAME}/{SNAPSHOT_NAME}?wait_for_completion=true",
        {
            "indices": "*",
            "ignore_unavailable": True,
            "include_global_state": False,
        }
    )
    if status not in ("200", "201"):
        print(f"  FAILED to create snapshot: HTTP {status} {err}")
        sys.exit(1)
    print(f"  Snapshot '{SNAPSHOT_NAME}' created.")


# ========== PHASE 3: VERIFY & METADATA ==========

def phase3_verify_and_metadata():
    print("\n" + "=" * 60)
    print(" PHASE 3: Verify Snapshot & Write Metadata")
    print("=" * 60)

    s_status, s_data, _ = curl_get_raw(
        f"{SOURCE_ES_URL}/_snapshot/{REPOSITORY_NAME}/{SNAPSHOT_NAME}"
    )
    if s_status != "200" or not s_data or not s_data.get("snapshots"):
        print(f"  FAILED: Could not read snapshot info (HTTP {s_status}).")
        sys.exit(1)

    snap = s_data["snapshots"][0]
    state     = snap.get("state", "UNKNOWN")
    indices   = snap.get("indices", [])
    shards    = snap.get("shards", {})
    total     = shards.get("total", 0)
    ok_shards = shards.get("successful", 0)
    failed    = shards.get("failed", 0)

    print(f"  State:              {state}")
    print(f"  Indices:            {len(indices)}")
    print(f"  Shards (ok/total):  {ok_shards}/{total}")
    print(f"  Failed shards:      {failed}")

    if state != "SUCCESS":
        print(f"  FAILED: Snapshot state is '{state}' (expected SUCCESS).")
        sys.exit(1)
    if failed > 0:
        print(f"  FAILED: {failed} shard(s) failed during snapshot.")
        sys.exit(1)

    print(f"\n  Snapshot is stored at: {AZURE_CONTAINER_NAME}/{AZURE_BASE_PATH}/")


# ========== MAIN ==========

def main():
    print("=" * 60)
    print(" Elasticsearch Snapshot → Azure Blob Storage")
    print("=" * 60)
    print(f"  SOURCE_ES_URL:        {SOURCE_ES_URL}")
    print(f"  AZURE_CONTAINER_NAME: {AZURE_CONTAINER_NAME}")
    print(f"  AZURE_BASE_PATH:      {AZURE_BASE_PATH}")
    print(f"  REPOSITORY_NAME:      {REPOSITORY_NAME}")
    print(f"  SNAPSHOT_NAME:        {SNAPSHOT_NAME}")
    print(f"  SOURCE_ES_POD:        {SOURCE_ES_POD_NAME} (ns: {SOURCE_ES_NAMESPACE})")
    print("=" * 60)

    validate_env_vars()
    phase1_add_keystore_credentials()
    phase2_create_snapshot()
    phase3_verify_and_metadata()

    print("\n" + "=" * 60)
    print(" SNAPSHOT COMPLETE — stored in Azure Blob Storage")
    print("=" * 60)
    sys.exit(0)


if __name__ == "__main__":
    main()
