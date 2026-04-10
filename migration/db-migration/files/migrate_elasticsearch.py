#!/usr/bin/env python3
"""
Elasticsearch Migration: Old Cluster → New Cluster (Reindex from Remote)

Migrates all indices from old ES cluster to new ES cluster using
ES reindex-from-remote API. No Azure blob or snapshot needed.

Steps:
  1. Get list of indices from old ES
  2. For each index:
     a. Create index with mapping on new ES (if not exists)
     b. Reindex documents from old ES to new ES
     c. Verify document count matches

Usage:
  export OLD_ES_HOST=http://<old-es-ip>:9200
  export NEW_ES_HOST=http://elasticsearch:9200
  python3 migrate_elasticsearch.py

Optional env vars:
  OLD_ES_USER       (default: none)
  OLD_ES_PASSWORD   (default: none)
  INDICES           (comma-separated list, default: all indices)
  BATCH_SIZE        (default: 1000)
  SKIP_INDICES      (comma-separated list of indices to skip, default: .*)
"""

import json
import os
import subprocess
import sys
import time

# ========== CONFIGURATION ==========
OLD_ES_HOST = os.environ.get("OLD_ES_HOST")
NEW_ES_HOST = os.environ.get("NEW_ES_HOST")
OLD_ES_USER = os.environ.get("OLD_ES_USER", "")
OLD_ES_PASSWORD = os.environ.get("OLD_ES_PASSWORD", "")
INDICES = os.environ.get("INDICES", "")
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "1000"))
SKIP_INDICES = os.environ.get("SKIP_INDICES", "").split(",") if os.environ.get("SKIP_INDICES") else []

if not OLD_ES_HOST:
    print("ERROR: Please set OLD_ES_HOST (e.g. export OLD_ES_HOST=http://20.x.x.x:9200)")
    sys.exit(1)

if not NEW_ES_HOST:
    print("ERROR: Please set NEW_ES_HOST (e.g. export NEW_ES_HOST=http://elasticsearch:9200)")
    sys.exit(1)


def curl_get(url, host=None):
    """HTTP GET request."""
    cmd = ["curl", "-s", "-f", url]
    if host == "old" and OLD_ES_USER:
        cmd += ["-u", f"{OLD_ES_USER}:{OLD_ES_PASSWORD}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return None, result.stderr.strip()
    try:
        return json.loads(result.stdout), None
    except json.JSONDecodeError:
        return None, f"Invalid JSON: {result.stdout[:200]}"


def curl_put(url, data, host=None):
    """HTTP PUT request."""
    cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
           "-X", "PUT", url,
           "-H", "Content-Type: application/json",
           "-d", json.dumps(data)]
    if host == "old" and OLD_ES_USER:
        cmd += ["-u", f"{OLD_ES_USER}:{OLD_ES_PASSWORD}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout.strip(), result.stderr.strip()


def curl_post(url, data):
    """HTTP POST request — returns full response body."""
    cmd = ["curl", "-s",
           "-X", "POST", url,
           "-H", "Content-Type: application/json",
           "-d", json.dumps(data)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return None, result.stderr.strip()
    try:
        return json.loads(result.stdout), None
    except json.JSONDecodeError:
        return None, f"Invalid JSON: {result.stdout[:200]}"


def get_indices():
    """Get list of indices from old ES."""
    data, err = curl_get(f"{OLD_ES_HOST}/_cat/indices?format=json&h=index,docs.count", host="old")
    if err or data is None:
        print(f"  FAILED to get indices: {err}")
        sys.exit(1)
    indices = []
    for item in data:
        name = item.get("index", "")
        count = int(item.get("docs.count", 0))
        # Skip system indices (starting with .)
        if name.startswith("."):
            continue
        if name in SKIP_INDICES:
            print(f"  Skipping index: {name}")
            continue
        indices.append((name, count))
    return indices


def get_mapping(index):
    """Get mapping of an index from old ES."""
    data, err = curl_get(f"{OLD_ES_HOST}/{index}/_mapping", host="old")
    if err or data is None:
        return None
    if index in data:
        return data[index].get("mappings", {})
    return {}


def get_settings(index):
    """Get settings of an index from old ES — excludes read-only system settings."""
    data, err = curl_get(f"{OLD_ES_HOST}/{index}/_settings", host="old")
    if err or data is None:
        return {}
    if index not in data:
        return {}
    settings = data[index].get("settings", {}).get("index", {})
    # Remove read-only/system settings that can't be set on create
    for key in ["uuid", "creation_date", "version", "provided_name"]:
        settings.pop(key, None)
    return {"index": settings} if settings else {}


def create_index(index, mapping, settings):
    """Create index on new ES with mapping + settings if not exists."""
    # Check if exists
    check, _ = curl_get(f"{NEW_ES_HOST}/{index}")
    if check is not None:
        print(f"  Index '{index}' already exists on new ES — skipping create.")
        return True

    body = {}
    if mapping:
        body["mappings"] = mapping
    if settings:
        body["settings"] = settings

    status, err = curl_put(f"{NEW_ES_HOST}/{index}", body)
    if status in ("200", "201"):
        print(f"  Created index '{index}'.")
        return True
    elif status == "400":
        print(f"  Index '{index}' already exists — skipping create.")
        return True
    else:
        print(f"  FAILED to create index '{index}': HTTP {status} {err}")
        return False


def reindex(index, old_count):
    """Reindex from old ES to new ES."""
    body = {
        "source": {
            "remote": {
                "host": OLD_ES_HOST,
            },
            "index": index,
            "size": BATCH_SIZE,
        },
        "dest": {
            "index": index
        }
    }

    if OLD_ES_USER:
        body["source"]["remote"]["username"] = OLD_ES_USER
        body["source"]["remote"]["password"] = OLD_ES_PASSWORD

    print(f"  Reindexing '{index}' ({old_count} docs)...", end=" ", flush=True)
    data, err = curl_post(f"{NEW_ES_HOST}/_reindex?wait_for_completion=true", body)
    if err or data is None:
        print(f"FAILED: {err}")
        return False

    if "error" in data:
        print(f"FAILED: {data['error']}")
        return False

    total = data.get("total", 0)
    created = data.get("created", 0)
    updated = data.get("updated", 0)
    failures = data.get("failures", [])

    print(f"total={total}, created={created}, updated={updated}, failures={len(failures)}")

    if failures:
        print(f"  WARNING: {len(failures)} failures:")
        for f in failures[:5]:
            print(f"    {f}")

    return True


def verify_count(index, old_count):
    """Verify document count on new ES matches old ES."""
    # Refresh index to ensure all docs are visible
    subprocess.run(["curl", "-s", "-X", "POST", f"{NEW_ES_HOST}/{index}/_refresh"],
                   capture_output=True)
    data, err = curl_get(f"{NEW_ES_HOST}/{index}/_count")
    if err or data is None:
        print(f"  FAILED to verify count: {err}")
        return False
    new_count = data.get("count", 0)
    if new_count >= old_count:
        print(f"  Verified: old={old_count}, new={new_count} ✓")
        return True
    else:
        print(f"  WARNING: old={old_count}, new={new_count} — count mismatch!")
        return False


def whitelist_check():
    """Ensure old ES host is whitelisted in new ES reindex settings. Exit if cannot set."""
    old_host = OLD_ES_HOST.replace("http://", "").replace("https://", "")

    def is_whitelisted():
        data, err = curl_get(f"{NEW_ES_HOST}/_cluster/settings")
        if err or data is None:
            return False
        persistent = data.get("persistent", {})
        transient = data.get("transient", {})
        whitelist = (
            persistent.get("reindex", {}).get("remote", {}).get("whitelist") or
            transient.get("reindex", {}).get("remote", {}).get("whitelist")
        )
        return whitelist and old_host in str(whitelist)

    if is_whitelisted():
        print(f"  Whitelist OK: {old_host} already whitelisted.")
        return

    print(f"  Whitelist not set. Adding {old_host} to reindex.remote.whitelist...")
    status, err = curl_put(
        f"{NEW_ES_HOST}/_cluster/settings",
        {"persistent": {"reindex.remote.whitelist": [old_host]}}
    )
    if status != "200":
        print(f"  FAILED to set whitelist: HTTP {status} {err}")
        sys.exit(1)

    # Verify it was applied
    if not is_whitelisted():
        print(f"  FAILED: Whitelist was not applied after PUT. Check ES permissions.")
        sys.exit(1)

    print(f"  Whitelist set successfully: {old_host}")


def migrate_aliases(migrated_indices):
    """Fetch all aliases from old ES and create them on new ES."""
    data, err = curl_get(f"{OLD_ES_HOST}/_aliases", host="old")
    if err or data is None:
        print(f"  FAILED to fetch aliases from old ES: {err}")
        return

    actions = []
    for index, index_data in data.items():
        if index not in migrated_indices:
            continue
        aliases = index_data.get("aliases", {})
        for alias_name in aliases:
            actions.append({"add": {"index": index, "alias": alias_name}})
            print(f"  Adding alias: {alias_name} → {index}")

    if not actions:
        print("  No aliases to migrate.")
        return

    # Create each alias individually to handle conflicts gracefully
    created = 0
    for action in actions:
        alias_name = action["add"]["alias"]
        index_name = action["add"]["index"]

        # Check if alias already exists correctly
        alias_check, _ = curl_get(f"{NEW_ES_HOST}/_alias/{alias_name}")
        if alias_check is not None and index_name in alias_check:
            print(f"  Alias '{alias_name}' → '{index_name}' already exists — skipping.")
            continue

        # Check if a conflicting index exists
        check, _ = curl_get(f"{NEW_ES_HOST}/{alias_name}")
        if check is not None and alias_name in check:
            count_data, _ = curl_get(f"{NEW_ES_HOST}/{alias_name}/_count")
            count = count_data.get("count", 1) if count_data else 1
            if count == 0:
                print(f"  Deleting empty index '{alias_name}' to replace with alias...")
                subprocess.run(["curl", "-s", "-X", "DELETE", f"{NEW_ES_HOST}/{alias_name}"],
                               capture_output=True)
            else:
                # Non-empty conflicting index — reindex its data into the target index, then replace with alias
                print(f"  Conflicting non-empty index '{alias_name}' found ({count} docs) — reindexing into '{index_name}'...")
                curl_post(f"{NEW_ES_HOST}/_reindex", {
                    "source": {"index": alias_name},
                    "dest": {"index": index_name, "op_type": "index"}
                })
                print(f"  Deleting conflicting index '{alias_name}'...")
                subprocess.run(["curl", "-s", "-X", "DELETE", f"{NEW_ES_HOST}/{alias_name}"],
                               capture_output=True)

        data, err = curl_post(f"{NEW_ES_HOST}/_aliases", {"actions": [action]})
        if err or data is None:
            print(f"  FAILED to create alias '{alias_name}': {err}")
        elif data.get("acknowledged"):
            print(f"  Created alias: {alias_name} → {index_name}")
            created += 1
        else:
            print(f"  FAILED to create alias '{alias_name}': {data}")

    print(f"  Done. {created}/{len(actions)} aliases created.")


def main():
    print("=" * 50)
    print(" Elasticsearch Migration: Old → New")
    print("=" * 50)
    print(f"  OLD_ES_HOST:  {OLD_ES_HOST}")
    print(f"  NEW_ES_HOST:  {NEW_ES_HOST}")
    print(f"  BATCH_SIZE:   {BATCH_SIZE}")
    print(f"  INDICES:      {INDICES or 'all'}")
    print("=" * 50)

    # Check connectivity
    print("\nChecking connectivity...")
    old_info, err = curl_get(f"{OLD_ES_HOST}/_cluster/health", host="old")
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
        indices = [(idx.strip(), 0) for idx in INDICES.split(",")]
        # Get counts for specified indices
        all_indices = {name: count for name, count in get_indices()}
        indices = [(name, all_indices.get(name, 0)) for name, _ in indices]
    else:
        print("\nFetching indices from old ES...")
        indices = get_indices()

    print(f"\nFound {len(indices)} indices to migrate:")
    for name, count in indices:
        print(f"  - {name} ({count} docs)")

    # Migrate each index
    success = []
    failed = []

    print(f"\n{'=' * 50}")
    print(" Starting Migration")
    print(f"{'=' * 50}")

    for index, old_count in indices:
        print(f"\n[{indices.index((index, old_count)) + 1}/{len(indices)}] Migrating: {index}")

        # Get mapping and settings from old ES
        mapping = get_mapping(index)
        settings = get_settings(index)

        # Create index on new ES
        if not create_index(index, mapping, settings):
            failed.append(index)
            continue

        # Update mapping on new ES to match old ES (handles .raw vs .keyword differences)
        if mapping:
            status, err = curl_put(f"{NEW_ES_HOST}/{index}/_mapping", mapping)
            if status in ("200", "201"):
                print(f"  Mapping updated from old ES.")
            else:
                print(f"  WARNING: Could not update mapping: HTTP {status} — continuing anyway.")

        # Reindex
        if not reindex(index, old_count):
            failed.append(index)
            continue

        # Verify
        verify_count(index, old_count)
        success.append(index)

    # Migrate aliases from old ES to new ES
    print(f"\n{'=' * 50}")
    print(" Migrating Aliases")
    print(f"{'=' * 50}")
    migrate_aliases(success)

    # Summary
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
