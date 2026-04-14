#!/usr/bin/env python3
"""
Elasticsearch Migration using elasticdump
Migrates indices from old ES to new ES via HTTP (no kubectl to old cluster needed).

Steps:
  1. Get list of indices from old ES
  2. For each index:
     a. Dump analyzer/settings from old ES → apply to new ES
     b. Dump mapping from old ES → apply to new ES
     c. Dump data from old ES → new ES
     d. Verify count
  3. Migrate aliases from old ES to new ES

Usage:
  export OLD_ES_HOST=http://20.219.175.25:9200
  export NEW_ES_HOST=http://elasticsearch.sunbird.svc.cluster.local:9200
  python3 migrate_elasticsearch.py
"""

import json
import os
import subprocess
import sys
import time

# ========== CONFIGURATION ==========
OLD_ES_HOST  = os.environ.get("OLD_ES_HOST", "http://20.219.175.25:9200")
NEW_ES_HOST  = os.environ.get("NEW_ES_HOST", "http://elasticsearch.sunbird.svc.cluster.local:9200")
INDICES      = os.environ.get("INDICES", "")
BATCH_SIZE   = int(os.environ.get("BATCH_SIZE", "1000"))
SKIP_INDICES = os.environ.get("SKIP_INDICES", "").split(",") if os.environ.get("SKIP_INDICES") else []


def run_cmd(cmd, timeout=3600):
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return result


def curl_get(url, host=None):
    cmd = ["curl", "-s", "-f", url]
    result = run_cmd(cmd)
    if result.returncode != 0:
        return None, result.stderr.strip()
    try:
        return json.loads(result.stdout), None
    except:
        return None, f"Invalid JSON: {result.stdout[:200]}"


def curl_put(url, data):
    cmd = ["curl", "-s", "-X", "PUT", url,
           "-H", "Content-Type: application/json",
           "-d", json.dumps(data)]
    result = run_cmd(cmd)
    try:
        return json.loads(result.stdout), None
    except:
        return None, result.stdout[:200]


def curl_post(url, data=None):
    cmd = ["curl", "-s", "-X", "POST", url,
           "-H", "Content-Type: application/json"]
    if data:
        cmd += ["-d", json.dumps(data)]
    result = run_cmd(cmd)
    try:
        return json.loads(result.stdout), None
    except:
        return None, result.stdout[:200]


def get_indices():
    data, err = curl_get(f"{OLD_ES_HOST}/_cat/indices?format=json&h=index,docs.count")
    if err or data is None:
        print(f"  FAILED to get indices: {err}")
        sys.exit(1)
    indices = []
    for item in data:
        name = item.get("index", "")
        count = int(item.get("docs.count", 0) or 0)
        if name.startswith("."):
            continue
        if name in SKIP_INDICES:
            print(f"  Skipping: {name}")
            continue
        indices.append((name, count))
    return indices


def elasticdump(input_url, output_url, dump_type, batch_size=1000):
    """Run elasticdump for a specific type."""
    cmd = [
        "elasticdump",
        f"--input={input_url}",
        f"--output={output_url}",
        f"--type={dump_type}",
        f"--limit={batch_size}",
        "--noRefresh"
    ]
    result = run_cmd(cmd, timeout=7200)
    return result.returncode == 0, result.stdout, result.stderr


def migrate_index(index, old_count):
    print(f"  Migrating settings...")
    ok, stdout, stderr = elasticdump(
        f"{OLD_ES_HOST}/{index}",
        f"{NEW_ES_HOST}/{index}",
        "settings"
    )
    if not ok:
        print(f"  WARNING: settings dump failed: {stderr[:100]}")

    print(f"  Migrating analyzer...")
    ok, stdout, stderr = elasticdump(
        f"{OLD_ES_HOST}/{index}",
        f"{NEW_ES_HOST}/{index}",
        "analyzer"
    )
    if not ok:
        print(f"  WARNING: analyzer dump failed: {stderr[:100]}")

    print(f"  Migrating mapping...")
    ok, stdout, stderr = elasticdump(
        f"{OLD_ES_HOST}/{index}",
        f"{NEW_ES_HOST}/{index}",
        "mapping"
    )
    if not ok:
        print(f"  WARNING: mapping dump failed: {stderr[:100]}")

    print(f"  Migrating data ({old_count} docs)...")
    ok, stdout, stderr = elasticdump(
        f"{OLD_ES_HOST}/{index}",
        f"{NEW_ES_HOST}/{index}",
        "data",
        BATCH_SIZE
    )
    if not ok:
        print(f"  FAILED: data dump failed: {stderr[:200]}")
        return False

    # Refresh
    subprocess.run(["curl", "-s", "-X", "POST", f"{NEW_ES_HOST}/{index}/_refresh"],
                   capture_output=True)

    # Verify count
    count_data, _ = curl_get(f"{NEW_ES_HOST}/{index}/_count")
    new_count = count_data.get("count", 0) if count_data else 0
    if new_count >= old_count:
        print(f"  Verified: old={old_count}, new={new_count} ✓")
    else:
        print(f"  WARNING: old={old_count}, new={new_count} — count mismatch!")

    return True


def migrate_aliases(migrated_indices):
    print(f"\n{'=' * 50}")
    print(" Migrating Aliases")
    print(f"{'=' * 50}")

    data, err = curl_get(f"{OLD_ES_HOST}/_aliases")
    if err or data is None:
        print(f"  FAILED to fetch aliases: {err}")
        return

    created = 0
    for index, index_data in data.items():
        if index not in migrated_indices:
            continue
        aliases = index_data.get("aliases", {})
        for alias_name in aliases:
            alias_check, _ = curl_get(f"{NEW_ES_HOST}/_alias/{alias_name}")
            if alias_check is not None and index in alias_check:
                print(f"  Alias '{alias_name}' → '{index}' already exists — skipping.")
                continue

            check, _ = curl_get(f"{NEW_ES_HOST}/{alias_name}")
            if check is not None and alias_name in check:
                count_data, _ = curl_get(f"{NEW_ES_HOST}/{alias_name}/_count")
                count = count_data.get("count", 1) if count_data else 1
                if count == 0:
                    print(f"  Deleting empty index '{alias_name}'...")
                    subprocess.run(["curl", "-s", "-X", "DELETE", f"{NEW_ES_HOST}/{alias_name}"],
                                   capture_output=True)
                else:
                    print(f"  Conflicting non-empty index '{alias_name}' ({count} docs) — reindexing into '{index}'...")
                    curl_post(f"{NEW_ES_HOST}/_reindex", {
                        "source": {"index": alias_name},
                        "dest": {"index": index, "op_type": "index"}
                    })
                    print(f"  Deleting conflicting index '{alias_name}'...")
                    subprocess.run(["curl", "-s", "-X", "DELETE", f"{NEW_ES_HOST}/{alias_name}"],
                                   capture_output=True)

            action = {"actions": [{"add": {"index": index, "alias": alias_name}}]}
            result_data, err = curl_post(f"{NEW_ES_HOST}/_aliases", action)
            if result_data and result_data.get("acknowledged"):
                print(f"  Created alias: {alias_name} → {index}")
                created += 1
            else:
                print(f"  FAILED alias '{alias_name}': {err or result_data}")

    print(f"  Done. {created} aliases created.")


def main():
    print("=" * 50)
    print(" Elasticsearch Migration (elasticdump)")
    print("=" * 50)
    print(f"  OLD_ES_HOST: {OLD_ES_HOST}")
    print(f"  NEW_ES_HOST: {NEW_ES_HOST}")
    print(f"  BATCH_SIZE:  {BATCH_SIZE}")
    print(f"  INDICES:     {INDICES or 'all'}")
    print("=" * 50)

    # Check elasticdump
    result = run_cmd(["elasticdump", "--version"])
    if result.returncode != 0:
        print("ERROR: elasticdump not found. Install with: npm install -g elasticdump")
        sys.exit(1)
    print(f"\nelasticdump version: {result.stdout.strip()}")

    # Check connectivity
    print("\nChecking connectivity...")
    old_info, err = curl_get(f"{OLD_ES_HOST}/_cluster/health")
    if old_info is None:
        print(f"  FAILED to connect to old ES: {err}")
        sys.exit(1)
    print(f"  Old ES: {old_info.get('cluster_name')} — {old_info.get('status')}")

    new_info, err = curl_get(f"{NEW_ES_HOST}/_cluster/health")
    if new_info is None:
        print(f"  FAILED to connect to new ES: {err}")
        sys.exit(1)
    print(f"  New ES: {new_info.get('cluster_name')} — {new_info.get('status')}")

    # Get indices
    if INDICES:
        all_indices = {name: count for name, count in get_indices()}
        indices = [(idx.strip(), all_indices.get(idx.strip(), 0)) for idx in INDICES.split(",")]
    else:
        print("\nFetching indices from old ES...")
        indices = get_indices()

    print(f"\nFound {len(indices)} indices to migrate:")
    for name, count in indices:
        print(f"  - {name} ({count} docs)")

    success = []
    failed = []

    print(f"\n{'=' * 50}")
    print(" Starting Migration")
    print(f"{'=' * 50}")

    for index, old_count in indices:
        print(f"\n[{indices.index((index, old_count)) + 1}/{len(indices)}] Migrating: {index}")
        if migrate_index(index, old_count):
            success.append(index)
        else:
            failed.append(index)

    migrate_aliases(set(success))

    print(f"\n{'=' * 50}")
    print(" Migration Summary")
    print(f"{'=' * 50}")
    print(f"  Total:   {len(indices)}")
    print(f"  Success: {len(success)}")
    print(f"  Failed:  {len(failed)}")
    if failed:
        print(f"\n  Failed indices:")
        for idx in failed:
            print(f"    - {idx}")
        sys.exit(1)
    else:
        print("\n  All indices migrated successfully!")


if __name__ == "__main__":
    main()
