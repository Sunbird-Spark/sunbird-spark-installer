#!/usr/bin/env python3
"""
1. Runs two System Settings requests from the Lern folder (requires apikey only):
     - 29 - System Settings - privacyPolicyConfig
     - 36 - System Settings - googleClientId
2. For every form in '3 - Forms', reads first and creates if missing (404).
   Skips: 4 - Page Create, 3 - Page Section Create.

Usage (called via install.sh):
  ./install.sh migrate_forms

Usage (direct):
  python3 migration/migrate_forms.py --env env.json --collection sunbird-spark-collection-v1.json
"""
import json
import re
import sys
import argparse
import urllib.request
import urllib.error


def load_env(path):
    with open(path) as f:
        data = json.load(f)
    return {v["key"]: v["value"] for v in data["values"] if v.get("enabled", True)}


def resolve_vars(text, env):
    return re.sub(r'\{\{(\w+)\}\}', lambda m: env.get(m.group(1), m.group(0)), text)


def find_by_name(items, name):
    for item in items:
        if item.get("name") == name:
            return item
        if "item" in item:
            found = find_by_name(item["item"], name)
            if found:
                return found
    return None


def find_folder(items, name):
    for item in items:
        if item.get("name") == name and "item" in item:
            return item
        if "item" in item:
            found = find_folder(item["item"], name)
            if found:
                return found
    return None


def collect_requests(items):
    out = []
    for item in items:
        if "item" in item:
            out.extend(collect_requests(item["item"]))
        elif "request" in item:
            out.append(item)
    return out


def http_post(url, apikey, raw_body):
    status, _ = http_post_full(url, apikey, raw_body)
    return status


def http_post_full(url, apikey, raw_body):
    """Returns (status, body_str). body_str is '' on non-HTTPError exception."""
    req = urllib.request.Request(url, data=raw_body.encode(), headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {apikey}",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read().decode("utf-8", errors="replace")
        except Exception:
            return e.code, ""
    except Exception as e:
        return f"ERROR: {e}", ""


def run_system_settings(collection, env, host, apikey):
    targets = [
        "29 - System Settings -  privacyPolicyConfig",
        "36 - System Settings - googleClientId",
    ]
    print("Running System Settings\n")
    print(f"{'Name':<55} {'Status'}")
    print("-" * 65)

    for target in targets:
        req = find_by_name(collection["item"], target)
        if not req:
            print(f"{target:<55} NOT FOUND in collection")
            continue

        raw_url = req["request"]["url"]
        url = resolve_vars(raw_url if isinstance(raw_url, str) else raw_url.get("raw", ""), env)
        raw_body = resolve_vars(req["request"]["body"]["raw"], env)

        status = http_post(url, apikey, raw_body)
        print(f"{target:<55} {status}")

    print()


def main():
    parser = argparse.ArgumentParser(
        description="Run System Settings and form setup from the Postman collection."
    )
    parser.add_argument(
        "--collection",
        default="postman-collection/sunbird-spark-collection-v1.json",
        help="Path to the Postman collection JSON file",
    )
    parser.add_argument(
        "--env",
        default="env.json",
        help="Path to a Postman environment JSON file",
    )
    args = parser.parse_args()

    try:
        env = load_env(args.env)
    except FileNotFoundError:
        print(f"ERROR: env file not found: {args.env}")
        sys.exit(1)

    host = env.get("host", "").rstrip("/")
    apikey = env.get("apikey", "")

    if not host or not apikey:
        print("ERROR: 'host' and 'apikey' must be present in the env file")
        sys.exit(1)

    try:
        with open(args.collection) as f:
            collection = json.load(f)
    except FileNotFoundError:
        print(f"ERROR: collection file not found: {args.collection}")
        sys.exit(1)

    print(f"\nHost : {host}\n")

    # Step 1: run System Settings before forms
    run_system_settings(collection, env, host, apikey)

    # Step 2: setup forms
    forms_folder = find_folder(collection["item"], "3 - Forms")
    if not forms_folder:
        print("ERROR: '3 - Forms' folder not found in collection")
        sys.exit(1)

    all_requests = collect_requests(forms_folder["item"])
    skip = {"4 - Page Create", "3 - Page Section Create"}
    read_url = f"{host}/api/data/v1/form/read"
    update_url = f"{host}/api/data/v1/form/update"

    print(f"Forms: {len(all_requests)} requests found in '3 - Forms'\n")
    print(f"{'API Name':<55} {'Read':<8} {'Create':<8} {'Update'}")
    print("-" * 80)

    for req in all_requests:
        name = req["name"]
        if name in skip:
            continue

        try:
            raw = req["request"]["body"]["raw"]
            body_src = json.loads(raw)["request"]
        except (KeyError, json.JSONDecodeError):
            print(f"{name:<55} SKIP (no parseable body)")
            continue

        read_body = json.dumps({
            "request": {
                "type":      body_src.get("type", "*"),
                "subType":   body_src.get("subType", "*"),
                "action":    body_src.get("action", "*"),
                "component": body_src.get("component", "*"),
                "framework": body_src.get("framework", "*"),
                "rootOrgId": body_src.get("rootOrgId", "*"),
            }
        })

        read_status, read_resp = http_post_full(read_url, apikey, read_body)

        # Substitute {{host}} (and other env vars) inside the body — without this,
        # raw {{host}} stays literal in payloads like Auth Config.
        resolved_body = resolve_vars(raw, env)

        create_status = ""
        update_status = ""

        if read_status == 404:
            create_url = resolve_vars(
                req["request"]["url"] if isinstance(req["request"]["url"], str)
                else req["request"]["url"].get("raw", ""), env
            )
            create_status = http_post(create_url, apikey, resolved_body)
        elif read_status == 200:
            # Compare server's stored form data with target — skip update if identical
            try:
                server_data = json.loads(read_resp)["result"]["form"]["data"]["fields"]
            except (KeyError, json.JSONDecodeError, TypeError):
                server_data = None
            try:
                target_data = json.loads(resolved_body)["request"]["data"]["fields"]
            except (KeyError, json.JSONDecodeError, TypeError):
                target_data = None

            if server_data is not None and server_data == target_data:
                update_status = "skip"
            else:
                update_status = http_post(update_url, apikey, resolved_body)

        print(f"{name:<55} {str(read_status):<8} {str(create_status):<8} {update_status}")

    print()


if __name__ == "__main__":
    main()
