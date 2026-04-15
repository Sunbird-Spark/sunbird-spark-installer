#!/usr/bin/env python3
"""
Migration script: Fix content_hierarchy identifiers.

Steps:
  1. Export identifiers from sb_hierarchy_store.content_hierarchy in YugaByte
     (uses ycqlsh COPY TO which handles pagination internally — avoids the
     default LIMIT truncation in interactive ycqlsh queries)
  2. Strip trailing '.img' from identifiers
  3. Remove duplicates
  4. For each unique identifier, POST to the knowlg-service hierarchy
     update-relation endpoint

Usage:
  python3 fix_hierarchy_identifiers.py

Optional env vars:
  YB_POD                (default: yb-tserver-0)
  YB_NAMESPACE          (default: sunbird)
  KEYSPACE              (default: sb_hierarchy_store — in-cluster this is
                         injected by the Helm Job as "<global.env>_hierarchy_store")
  TABLE                 (default: content_hierarchy)
  KNOWLG_SERVICE_HOST   (default: knowlg-service.sunbird.svc.cluster.local)
  KNOWLG_SERVICE_PORT   (default: 9000)
  API_DELAY_SECONDS     (default: 0.1)
  API_TIMEOUT_SECONDS   (default: 30)
  PROGRESS_EVERY        (default: 100)
  DRY_RUN               (default: false)  — if "true", skip API calls
"""

import os
import subprocess
import sys
import time
from datetime import datetime

# ========== CONFIGURATION ==========
YB_POD = os.environ.get("YB_POD", "yb-tserver-0")
YB_NAMESPACE = os.environ.get("YB_NAMESPACE", "sunbird")
KEYSPACE = os.environ.get("KEYSPACE", "sb_hierarchy_store")
TABLE = os.environ.get("TABLE", "content_hierarchy")

KNOWLG_SERVICE_HOST = os.environ.get(
    "KNOWLG_SERVICE_HOST", "knowlg-service.sunbird.svc.cluster.local"
)
KNOWLG_SERVICE_PORT = os.environ.get("KNOWLG_SERVICE_PORT", "9000")

API_DELAY_SECONDS = float(os.environ.get("API_DELAY_SECONDS", "0.1"))
API_TIMEOUT_SECONDS = int(os.environ.get("API_TIMEOUT_SECONDS", "30"))
PROGRESS_EVERY = int(os.environ.get("PROGRESS_EVERY", "100"))
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"

REMOTE_CSV = "/tmp/hierarchy_identifiers.csv"


def yb_exec(command, timeout=3600):
    """Execute a command on the YugaByte pod."""
    cmd = ["kubectl", "exec", YB_POD, "-n", YB_NAMESPACE, "--"] + command
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        print(f"  STDERR: {result.stderr.strip()}")
    return result


def step_1_export_identifiers():
    """
    Export identifiers from content_hierarchy using ycqlsh COPY TO.

    Why COPY TO instead of SELECT:
      Interactive ycqlsh queries paginate/truncate large result sets — only a
      small page is returned. COPY TO streams ALL rows to a file internally,
      which is the safe way to dump the full identifier set.
    """
    print("\n[Step 1/4] Exporting identifiers from YugaByte...")
    print(f"  Source: {KEYSPACE}.{TABLE}  (pod: {YB_POD}/{YB_NAMESPACE})")

    copy_cmd = (
        f"COPY {KEYSPACE}.{TABLE} (identifier) "
        f"TO '{REMOTE_CSV}' WITH HEADER=false AND PAGESIZE=5000;"
    )
    result = yb_exec(["ycqlsh", "-e", copy_cmd])
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)

    # The COPY output contains a row-count summary line — surface it.
    summary = result.stdout.strip().splitlines()
    for line in summary[-3:]:
        if line.strip():
            print(f"  {line.strip()}")
    print("  Done.")


def step_2_read_identifiers():
    """Read identifiers from the CSV inside the YugaByte pod."""
    print("\n[Step 2/4] Reading exported identifiers...")
    result = yb_exec(["cat", REMOTE_CSV])
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)

    raw = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    print(f"  Raw rows read: {len(raw)}")
    return raw


def step_3_clean_and_dedupe(raw_ids):
    """Strip trailing '.img' and deduplicate."""
    print("\n[Step 3/4] Stripping '.img' suffix and deduplicating...")
    img_suffix_count = 0
    cleaned = []
    for identifier in raw_ids:
        if identifier.endswith(".img"):
            cleaned.append(identifier[:-4])
            img_suffix_count += 1
        else:
            cleaned.append(identifier)

    unique = sorted(set(cleaned))
    print(f"  .img suffixes stripped: {img_suffix_count}")
    print(f"  Duplicates removed    : {len(cleaned) - len(unique)}")
    print(f"  Unique identifiers    : {len(unique)}")
    return unique


def step_4_trigger_api(identifiers):
    """
    For each unique identifier, POST to the knowlg-service hierarchy
    update-relation endpoint. Relies on cluster DNS — since this script runs
    inside a Kubernetes Job in the same namespace as knowlg-service, it can
    reach the service directly without port-forwarding.
    """
    url_base = (
        f"http://{KNOWLG_SERVICE_HOST}:{KNOWLG_SERVICE_PORT}"
        f"/collection/v4/hierarchy/update/relation"
    )
    total = len(identifiers)
    print(f"\n[Step 4/4] Triggering hierarchy update-relation API for {total} identifiers")
    print(f"  Endpoint : POST {url_base}/<identifier>")
    print(f"  Delay    : {API_DELAY_SECONDS}s between calls")
    print(f"  DRY_RUN  : {DRY_RUN}")

    if DRY_RUN:
        print("  [DRY_RUN] Skipping API calls. Showing first 10 targets:")
        for identifier in identifiers[:10]:
            print(f"    would POST {url_base}/{identifier}")
        return 0, 0, []

    ok = 0
    failed = 0
    failures = []

    for idx, identifier in enumerate(identifiers, start=1):
        url = f"{url_base}/{identifier}"
        try:
            result = subprocess.run(
                [
                    "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                    "--max-time", str(API_TIMEOUT_SECONDS),
                    "-X", "POST", url,
                    "--data", "",
                ],
                capture_output=True, text=True, timeout=API_TIMEOUT_SECONDS + 10,
            )
            status = result.stdout.strip() or "000"
        except subprocess.TimeoutExpired:
            status = "TIMEOUT"

        if status.startswith("2"):
            ok += 1
        else:
            failed += 1
            failures.append((identifier, status))
            print(f"  [{idx}/{total}] {identifier} -> HTTP {status}")

        if idx % PROGRESS_EVERY == 0:
            print(f"  Progress: {idx}/{total}  (OK: {ok}, FAILED: {failed})")

        if API_DELAY_SECONDS > 0:
            time.sleep(API_DELAY_SECONDS)

    return ok, failed, failures


def main():
    start = datetime.now()
    print("=" * 60)
    print(" Migration: content_hierarchy identifier fix")
    print("=" * 60)
    print(f"  YB_POD              : {YB_POD}")
    print(f"  YB_NAMESPACE        : {YB_NAMESPACE}")
    print(f"  KEYSPACE.TABLE      : {KEYSPACE}.{TABLE}")
    print(f"  KNOWLG_SERVICE_HOST : {KNOWLG_SERVICE_HOST}")
    print(f"  KNOWLG_SERVICE_PORT : {KNOWLG_SERVICE_PORT}")
    print(f"  API_DELAY_SECONDS   : {API_DELAY_SECONDS}")
    print(f"  DRY_RUN             : {DRY_RUN}")
    print("=" * 60)

    step_1_export_identifiers()
    raw_ids = step_2_read_identifiers()
    unique_ids = step_3_clean_and_dedupe(raw_ids)

    if not unique_ids:
        print("\nNo identifiers to process. Exiting.")
        return

    ok, failed, failures = step_4_trigger_api(unique_ids)

    duration = (datetime.now() - start).total_seconds()
    print("\n" + "=" * 60)
    print(" Migration complete")
    print("=" * 60)
    print(f"  Unique identifiers : {len(unique_ids)}")
    print(f"  API OK             : {ok}")
    print(f"  API FAILED         : {failed}")
    print(f"  Duration           : {duration:.1f}s")
    print("=" * 60)

    if failures:
        print("\nFirst 20 failures:")
        for identifier, status in failures[:20]:
            print(f"  {identifier}  ->  HTTP {status}")
        sys.exit(1)


if __name__ == "__main__":
    main()
