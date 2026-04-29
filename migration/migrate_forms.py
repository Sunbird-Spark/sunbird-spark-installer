#!/usr/bin/env python3
"""
Run form/read API for all requests in the '3 - Forms' folder of the Postman collection.
For any form that returns 404 (not found), automatically runs the collection's create request.
Prints a table of: API name → read status → create status (if triggered)

Usage (called via install.sh):
  ./install.sh run_form_read

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


def resolve_url(url_field, env):
    raw = url_field if isinstance(url_field, str) else url_field.get("raw", "")
    return re.sub(r'\{\{(\w+)\}\}', lambda m: env.get(m.group(1), m.group(0)), raw)


def http_post(url, apikey, raw_body):
    req = urllib.request.Request(url, data=raw_body.encode(), headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {apikey}",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception as e:
        return f"ERROR: {e}"


def main():
    parser = argparse.ArgumentParser(
        description="Run form/read API for every form in the '3 - Forms' Postman collection folder. "
                    "Auto-creates forms that return 404."
    )
    parser.add_argument(
        "--collection",
        default="postman-collection/sunbird-spark-collection-v1.json",
        help="Path to the Postman collection JSON file",
    )
    parser.add_argument(
        "--env",
        default="env.json",
        help="Path to a Postman environment JSON file containing 'host' and 'apikey' values",
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

    forms_folder = find_folder(collection["item"], "3 - Forms")
    if not forms_folder:
        print("ERROR: '3 - Forms' folder not found in collection")
        sys.exit(1)

    all_requests = collect_requests(forms_folder["item"])
    skip = {"4 - Page Create", "3 - Page Section Create"}

    read_url = f"{host}/api/data/v1/form/read"

    print(f"\nHost : {host}")
    print(f"Forms: {len(all_requests)} requests found in '3 - Forms'\n")
    print(f"{'API Name':<55} {'Read':<8} {'Create'}")
    print("-" * 75)

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

        read_status = http_post(read_url, apikey, read_body)

        if read_status == 404:
            create_url = resolve_url(req["request"]["url"], env)
            create_status = http_post(create_url, apikey, raw)
            print(f"{name:<55} {str(read_status):<8} {create_status}")
        else:
            print(f"{name:<55} {read_status}")

    print()


if __name__ == "__main__":
    main()
