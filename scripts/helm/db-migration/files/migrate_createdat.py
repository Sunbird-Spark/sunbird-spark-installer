#!/usr/bin/env python3
"""
Migration script: Backfill createdat field for user creation count report.

Steps:
  1. Update ES mapping to add createdAt as date field
  2. Alter YugaByte table to add createdat column
  3. Export user data from YugaByte
  4. Backfill createdat from createddate
  5. Verify backfill
  6. Trigger data sync (batched, via localhost inside lern-service pod)

Usage:
  export ES_HOST=http://elasticsearch:9200
  python3 migrate_createdat.py

Optional env vars:
  YB_POD          (default: yb-tserver-0)
  YB_NAMESPACE    (default: sunbird)
  LERN_NAMESPACE  (default: sunbird)
  LERN_PORT       (default: 9000)
  KEYSPACE        (default: sunbird)
  SYNC_BATCH_SIZE (default: 500)
"""

import json
import os
import subprocess
import sys

# ========== CONFIGURATION ==========
ES_HOST = os.environ.get("ES_HOST")
YB_POD = os.environ.get("YB_POD", "yb-tserver-0")
YB_NAMESPACE = os.environ.get("YB_NAMESPACE", "sunbird")
LERN_NAMESPACE = os.environ.get("LERN_NAMESPACE", "sunbird")
LERN_PORT = os.environ.get("LERN_PORT", "9000")
KEYSPACE = os.environ.get("KEYSPACE", "sunbird")
SYNC_BATCH_SIZE = int(os.environ.get("SYNC_BATCH_SIZE", "500"))

if not ES_HOST:
    print("ERROR: Please set ES_HOST (e.g. export ES_HOST=http://elasticsearch:9200)")
    sys.exit(1)


def kubectl_exec(pod, namespace, command):
    """Execute a command on a pod."""
    cmd = ["kubectl", "exec", pod]
    if namespace:
        cmd = ["kubectl", "exec", pod, "-n", namespace]
    cmd += ["--"] + command
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  STDERR: {result.stderr.strip()}")
    return result


def yb_exec(command):
    """Execute a command on the YugaByte pod."""
    return kubectl_exec(YB_POD, YB_NAMESPACE, command)


def find_lern_pod():
    """Find the lern-service pod name using: kubectl get pods -n <ns> | grep lern"""
    cmd = ["kubectl", "get", "pods", "-n", LERN_NAMESPACE, "--no-headers"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  FAILED to list pods: {result.stderr.strip()}")
        sys.exit(1)
    for line in result.stdout.strip().split("\n"):
        if "lern" in line:
            pod_name = line.split()[0]
            print(f"  Found pod: {pod_name}")
            return pod_name
    print("  ERROR: No pod matching 'lern' found in namespace '{LERN_NAMESPACE}'.")
    sys.exit(1)


def confirm(message):
    """Prompt user for confirmation."""
    response = input(f"{message} (y/n): ").strip().lower()
    if response != "y":
        print("Aborted.")
        sys.exit(0)


def step_1_update_es_mapping():
    """Update ES mapping to add createdAt as date field."""
    print("\n[Step 1/6] Updating ES mapping...")
    result = subprocess.run(
        ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
         "-X", "PUT", f"{ES_HOST}/userv3/_mapping",
         "-H", "Content-Type: application/json",
         "-d", json.dumps({"properties": {"createdAt": {"type": "date", "format": "yyyy-MM-dd"}}})],
        capture_output=True, text=True
    )
    if result.stdout.strip() != "200":
        print(f"  FAILED: HTTP {result.stdout.strip()}")
        sys.exit(1)
    print("  Done.")


def step_2_alter_table():
    """Alter YugaByte table to add createdat column."""
    print("\n[Step 2/6] Altering YugaByte table...")
    result = yb_exec(["ycqlsh", "-e", f"ALTER TABLE {KEYSPACE}.user ADD createdat text;"])
    if result.returncode != 0:
        if "already exists" in result.stderr.lower() or "already exists" in result.stdout.lower():
            print("  WARNING: Column already exists. Continuing...")
        else:
            print(f"  WARNING: {result.stderr.strip()}. Continuing...")
    print("  Done.")


def step_3_export_users():
    """Export user IDs and createddate from YugaByte."""
    print("\n[Step 3/6] Exporting user data from YugaByte...")
    result = yb_exec([
        "ycqlsh", "-e",
        f"COPY {KEYSPACE}.user (id, createddate) TO '/tmp/users.csv' WITH HEADER=false;"
    ])
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)
    print("  Done.")


def step_4_backfill():
    """Generate and execute backfill statements on the pod."""
    print("\n[Step 4/6] Generating and executing backfill statements...")
    script = (
        f"awk -F',' '{{print \"UPDATE {KEYSPACE}.user SET createdat=\\x27\" "
        f"substr($2,1,10) \"\\x27 WHERE id=\\x27\" $1 \"\\x27;\"}}' "
        f"/tmp/users.csv > /tmp/backfill.cql && ycqlsh -f /tmp/backfill.cql"
    )
    result = yb_exec(["bash", "-c", script])
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)
    print("  Done.")


def step_5_verify():
    """Verify backfill with sample rows."""
    print("\n[Step 5/6] Verifying backfill...")
    result = yb_exec([
        "ycqlsh", "-e",
        f"SELECT id, createdat, createddate FROM {KEYSPACE}.user LIMIT 5;"
    ])
    print(result.stdout)
    confirm("Backfill looks correct? Proceed with data sync?")


def step_6_sync(lern_pod, user_ids):
    """Trigger data sync in batches via localhost inside lern-service pod."""
    total = len(user_ids)
    print(f"\n[Step 6/6] Triggering data sync for {total} users (batch size: {SYNC_BATCH_SIZE})...")

    for i in range(0, total, SYNC_BATCH_SIZE):
        batch = user_ids[i:i + SYNC_BATCH_SIZE]
        batch_num = (i // SYNC_BATCH_SIZE) + 1
        total_batches = (total + SYNC_BATCH_SIZE - 1) // SYNC_BATCH_SIZE
        print(f"  Batch {batch_num}/{total_batches} ({len(batch)} users)...", end=" ")

        payload = json.dumps({"request": {"objectType": "user", "objectIds": batch}})
        curl_cmd = (
            f"curl -s -o /dev/null -w '%{{http_code}}' "
            f"-X POST http://localhost:{LERN_PORT}/v1/data/sync "
            f"-H 'Content-Type: application/json' "
            f"-d '{payload}'"
        )
        result = kubectl_exec(lern_pod, LERN_NAMESPACE, ["bash", "-c", curl_cmd])
        status = result.stdout.strip()
        if status == "200":
            print("OK")
        else:
            print(f"FAILED (HTTP {status})")
            print(f"  {result.stderr.strip()}")

    print("  Done.")


def extract_user_ids():
    """Extract user IDs from the CSV on the pod."""
    print("\nExtracting user IDs from pod...")
    result = yb_exec(["bash", "-c", "awk -F',' '{print $1}' /tmp/users.csv"])
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)
    ids = [line.strip() for line in result.stdout.strip().split("\n") if line.strip()]
    print(f"  Found {len(ids)} users.")
    return ids


def main():
    print("==============================")
    print(" Migration: createdat backfill")
    print("==============================")
    print(f"  ES_HOST:        {ES_HOST}")
    print(f"  YB_POD:         {YB_POD}")
    print(f"  YB_NAMESPACE:   {YB_NAMESPACE}")
    print(f"  LERN_NAMESPACE: {LERN_NAMESPACE}")
    print(f"  LERN_PORT:      {LERN_PORT}")
    print(f"  KEYSPACE:       {KEYSPACE}")
    print(f"  BATCH_SIZE:     {SYNC_BATCH_SIZE}")
    print("==============================")

    print("\nFinding lern-service pod...")
    lern_pod = find_lern_pod()

    confirm("Proceed?")

    step_1_update_es_mapping()
    step_2_alter_table()
    step_3_export_users()
    step_4_backfill()
    step_5_verify()
    user_ids = extract_user_ids()
    step_6_sync(lern_pod, user_ids)

    print("\n==============================")
    print(" Migration complete!")
    print("==============================")
    print(f"\nVerify with:")
    print(f"  curl '{ES_HOST}/user_alias/_search?pretty' \\")
    print(f"    -H 'Content-Type: application/json' \\")
    print(f"    -d '{{\"query\":{{\"exists\":{{\"field\":\"createdAt\"}}}},\"_source\":[\"createdAt\"],\"size\":5}}'")


if __name__ == "__main__":
    main()
