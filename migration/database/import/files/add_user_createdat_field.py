#!/usr/bin/env python3
"""
Migration script: Backfill createdat field for user creation count report.

Steps:
  1. Update ES mapping to add createdAt as date field
  2. Backfill createdAt from oldCreatedDate in ES (_update_by_query)
  3. Verify ES backfill
  4. Alter YugaByte table to add createdat column
  5. Export user data from YugaByte
  6. Backfill createdat from createddate in YugaByte

Usage:
  python3 add_user_createdat_field.py

Optional env vars:
  ES_SERVICE  (default: elasticsearch:9200)
  YB_POD      (default: yb-tserver-0)
  NAMESPACE   (default: sunbird)
  KEYSPACE    (default: sunbird)
"""

import json
import os
import subprocess
import sys

# ========== CONFIGURATION ==========
ES_SERVICE = os.environ.get("ES_SERVICE", "elasticsearch:9200")
YB_POD = os.environ.get("YB_POD", "yb-tserver-0")
NAMESPACE = os.environ.get("NAMESPACE", "sunbird")
KEYSPACE = os.environ.get("KEYSPACE", "sunbird")


def yb_exec(command):
    """Execute a command on the YugaByte pod."""
    cmd = ["kubectl", "exec", YB_POD, "-n", NAMESPACE, "--"] + command
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  STDERR: {result.stderr.strip()}")
    return result


def confirm(message):
    """No-op in automated mode."""
    print(f"  [AUTO] {message} → proceeding automatically")


def es_curl(method, path, data=None):
    """Execute a curl command against ES from inside the YB pod."""
    curl_cmd = f"curl -s -X {method} http://{ES_SERVICE}/{path} -H 'Content-Type: application/json'"
    if data:
        payload = json.dumps(data)
        curl_cmd += f" -d '{payload}'"
    result = yb_exec(["bash", "-c", curl_cmd])
    return result.stdout.strip()


def es_index_exists(index_name):
    """Return True if the given ES index exists."""
    try:
        resp = es_curl("GET", f"{index_name}")
        parsed = json.loads(resp) if resp else {}
        return index_name in parsed and "error" not in parsed
    except Exception:
        return False


def step_1_update_es_mapping():
    """Update ES mapping to add createdAt as date field. Skips if userv3 missing."""
    print("\n[Step 1/6] Updating ES mapping...")
    if not es_index_exists("userv3"):
        print("  SKIP: ES index 'userv3' not found — skipping ES mapping/backfill steps.")
        return False
    response = es_curl("PUT", "userv3/_mapping", {
        "properties": {
            "createdAt": {
                "type": "date",
                "format": "yyyy-MM-dd"
            }
        }
    })
    parsed = json.loads(response)
    if parsed.get("acknowledged"):
        print("  Done.")
        return True
    else:
        print(f"  FAILED: {response}")
        sys.exit(1)


def step_2_es_backfill():
    """Backfill createdAt from oldCreatedDate in ES using _update_by_query."""
    print("\n[Step 2/6] Backfilling createdAt in ES from oldCreatedDate...")
    response = es_curl("POST", "user_alias/_update_by_query?refresh=true", {
        "script": {
            "source": "if (ctx._source.oldCreatedDate != null) { ctx._source.createdAt = ctx._source.oldCreatedDate.substring(0, 10); }",
            "lang": "painless"
        },
        "query": {
            "match_all": {}
        }
    })
    parsed = json.loads(response)
    total = parsed.get("total", 0)
    updated = parsed.get("updated", 0)
    failures = parsed.get("failures", [])
    print(f"  Total: {total}, Updated: {updated}, Failures: {len(failures)}")
    if failures:
        print(f"  First failure: {failures[0]}")
        sys.exit(1)
    print("  Done.")


def step_3_verify_es():
    """Verify ES backfill with sample documents."""
    print("\n[Step 3/6] Verifying ES backfill...")
    response = es_curl("POST", "user_alias/_search", {
        "query": {"exists": {"field": "createdAt"}},
        "_source": ["createdAt", "oldCreatedDate"],
        "size": 5
    })
    parsed = json.loads(response)
    total = parsed.get("hits", {}).get("total", {}).get("value", 0)
    print(f"  Documents with createdAt: {total}")
    for hit in parsed.get("hits", {}).get("hits", []):
        src = hit.get("_source", {})
        print(f"    {hit['_id']}: createdAt={src.get('createdAt')} (from {src.get('oldCreatedDate', 'N/A')})")
    confirm("ES backfill looks correct? Proceed with YugaByte backfill?")


def step_4_alter_table():
    """Alter YugaByte table to add createdat column."""
    print("\n[Step 4/6] Altering YugaByte table...")
    result = yb_exec(["ycqlsh", "-e", f"ALTER TABLE {KEYSPACE}.user ADD createdat text;"])
    if result.returncode != 0:
        if "already exists" in result.stderr.lower() or "already exists" in result.stdout.lower():
            print("  WARNING: Column already exists. Continuing...")
        else:
            print(f"  WARNING: {result.stderr.strip()}. Continuing...")
    print("  Done.")


def step_5_export_users():
    """Export user IDs and createddate from YugaByte."""
    print("\n[Step 5/6] Exporting user data from YugaByte...")
    result = yb_exec([
        "ycqlsh", "-e",
        f"COPY {KEYSPACE}.user (id, createddate) TO '/tmp/users.csv' WITH HEADER=false;"
    ])
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)
    print("  Done.")


def step_6_yb_backfill():
    """Generate backfill.cql on pod, then run ycqlsh -f detached + poll for completion.
    Long ycqlsh -f reset kubectl exec stream → use nohup + log polling instead."""
    import time
    print("\n[Step 6/6] Backfilling createdat in YugaByte from createddate...")

    # 1) Generate CQL file on pod (fast — single short exec)
    print("  Generating backfill.cql on pod...")
    gen_script = (
        f"awk -F',' '{{print \"UPDATE {KEYSPACE}.user SET createdat=\\x27\" "
        f"substr($2,1,10) \"\\x27 WHERE id=\\x27\" $1 \"\\x27;\"}}' "
        f"/tmp/users.csv > /tmp/backfill.cql && wc -l /tmp/backfill.cql"
    )
    result = yb_exec(["bash", "-c", gen_script])
    if result.returncode != 0:
        print(f"  FAILED to generate CQL: {result.stderr.strip()}")
        sys.exit(1)
    print(f"  {result.stdout.strip()}")

    # 2) Launch ycqlsh -f detached on pod with log + done sentinel
    print("  Launching ycqlsh -f in background on pod...")
    launch_script = (
        "rm -f /tmp/backfill.log /tmp/backfill.done && "
        "nohup bash -c 'ycqlsh -f /tmp/backfill.cql > /tmp/backfill.log 2>&1; "
        "echo $? > /tmp/backfill.done' >/dev/null 2>&1 & disown; echo started"
    )
    result = yb_exec(["bash", "-c", launch_script])
    if result.returncode != 0:
        print(f"  FAILED to launch: {result.stderr.strip()}")
        sys.exit(1)

    # 3) Poll for /tmp/backfill.done
    print("  Polling for completion (max 30 min)...")
    for i in range(180):  # 180 * 10s = 30 min
        time.sleep(10)
        check = yb_exec(["bash", "-c", "test -f /tmp/backfill.done && cat /tmp/backfill.done || echo running"])
        out = check.stdout.strip()
        if out == "running":
            if i % 6 == 0:
                # Every minute, print row count for progress
                tail = yb_exec(["bash", "-c", "wc -l /tmp/backfill.log 2>/dev/null || echo 0"])
                print(f"    [{(i+1)*10}s] still running, log lines: {tail.stdout.strip()}")
            continue
        rc = out
        print(f"  ycqlsh exit code: {rc}")
        if rc != "0":
            tail = yb_exec(["bash", "-c", "tail -20 /tmp/backfill.log"])
            print(f"  log tail:\n{tail.stdout}")
            sys.exit(1)
        break
    else:
        print("  TIMEOUT: backfill still running after 30min. Check pod /tmp/backfill.log manually.")
        sys.exit(1)

    # 4) Verify
    print("  Verifying...")
    result = yb_exec([
        "ycqlsh", "-e",
        f"SELECT id, createdat, createddate FROM {KEYSPACE}.user LIMIT 5;"
    ])
    print(result.stdout)
    print("  Done.")


def main():
    print("==============================")
    print(" Migration: createdat backfill")
    print("==============================")
    print(f"  ES_SERVICE: {ES_SERVICE}")
    print(f"  YB_POD:     {YB_POD}")
    print(f"  NAMESPACE:  {NAMESPACE}")
    print(f"  KEYSPACE:   {KEYSPACE}")
    print("==============================")

    confirm("Proceed?")

    es_ok = step_1_update_es_mapping()
    if es_ok:
        step_2_es_backfill()
        step_3_verify_es()
    else:
        print("\n[Step 2/6] SKIPPED (userv3 index not present)")
        print("[Step 3/6] SKIPPED (userv3 index not present)")
    step_4_alter_table()
    step_5_export_users()
    step_6_yb_backfill()

    print("\n==============================")
    print(" Migration complete!")
    print("==============================")


if __name__ == "__main__":
    main()