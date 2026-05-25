#!/usr/bin/env python3
"""
Migration script: Sync user course progress for all enrollments.

Steps:
  1. Get DOMAIN_URL + client secret from sunbird/player-env ConfigMap
  2. Request admin user token from Keycloak (password grant)
  3. Exchange refresh token at Sunbird /auth/v1/refresh/token endpoint
  4. Query YugabyteDB for all user enrollments (userid, courseid, batchid)
  5. For each enrollment, POST to lern-service /v1/activity/agg API

Usage:
  python3 user-progress-sync.py

Required env vars:
  ADMIN_USERNAME            — admin username for Keycloak
  ADMIN_PASSWORD            — admin password for Keycloak

Optional env vars:
  YB_POD                    (default: yb-tserver-0)
  YB_NAMESPACE              (default: sunbird)
  KEYSPACE                  (default: sunbird_courses)
  TABLE                     (default: user_enrolments)
  KEYCLOAK_REALM            (default: sunbird)
  KEYCLOAK_CLIENT_ID        (default: lms)
  LERN_SERVICE_HOST         (default: lern-service.sunbird.svc.cluster.local)
  LERN_SERVICE_PORT         (default: 9000)
  ACTIVITY_API_DELAY_SECONDS (default: 0.1)
  ACTIVITY_API_TIMEOUT_SECONDS (default: 30)
  PROGRESS_EVERY            (default: 100)
  DRY_RUN                   (default: false) — if "true", skip API calls
"""

import os
import subprocess
import sys
import time
import json
from datetime import datetime

# ========== CONFIGURATION ==========
YB_POD = os.environ.get("YB_POD", "yb-tserver-0")
YB_NAMESPACE = os.environ.get("YB_NAMESPACE", "sunbird")
KEYSPACE = os.environ.get("KEYSPACE", "sunbird_courses")
TABLE = os.environ.get("TABLE", "user_enrolments")

KEYCLOAK_REALM = os.environ.get("KEYCLOAK_REALM", "sunbird")
KEYCLOAK_CLIENT_ID = os.environ.get("KEYCLOAK_CLIENT_ID", "lms")

ADMIN_USERNAME = os.environ.get("ADMIN_USERNAME", "")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "")

LERN_SERVICE_HOST = os.environ.get("LERN_SERVICE_HOST", "lern-service.sunbird.svc.cluster.local")
LERN_SERVICE_PORT = os.environ.get("LERN_SERVICE_PORT", "9000")

ACTIVITY_API_DELAY_SECONDS = float(os.environ.get("ACTIVITY_API_DELAY_SECONDS", "0.1"))
ACTIVITY_API_TIMEOUT_SECONDS = int(os.environ.get("ACTIVITY_API_TIMEOUT_SECONDS", "30"))
PROGRESS_EVERY = int(os.environ.get("PROGRESS_EVERY", "100"))
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"

REMOTE_CSV = "/tmp/user_enrollments.csv"


def yb_exec(command, timeout=3600):
    """Execute a command on the YugaByte pod via kubectl."""
    cmd = ["kubectl", "exec", YB_POD, "-n", YB_NAMESPACE, "--"] + command
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        print(f"  STDERR: {result.stderr.strip()}")
    return result


def disable_enrollment_filter():
    """Disable filter_processed_enrolments in lern-env ConfigMap."""
    print("\n[Pre-job] Disabling filter_processed_enrolments in lern-env ConfigMap...")
    cmd = [
        "kubectl", "patch", "configmap", "lern-env", "-n", "sunbird",
        "--type", "merge",
        "-p", '{"data":{"filter_processed_enrolments":"false"}}'
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  WARNING: Could not disable filter. {result.stderr.strip()}")
        print("  Continuing anyway...")
    else:
        print("  Filter disabled successfully")


def enable_enrollment_filter():
    """Re-enable filter_processed_enrolments in lern-env ConfigMap."""
    print("\n[Post-job] Re-enabling filter_processed_enrolments in lern-env ConfigMap...")
    cmd = [
        "kubectl", "patch", "configmap", "lern-env", "-n", "sunbird",
        "--type", "merge",
        "-p", '{"data":{"filter_processed_enrolments":"true"}}'
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  WARNING: Could not re-enable filter. {result.stderr.strip()}")
    else:
        print("  Filter re-enabled successfully")


def step_1_get_config_from_configmap():
    """Fetch DOMAIN_URL + client secret from ConfigMap."""
    print("\n[Step 1/6] Fetching config from sunbird/player-env ConfigMap...")

    cmd = [
        "kubectl", "get", "cm", "-n", "sunbird", "player-env",
        "-ojsonpath={.data.DOMAIN_URL}"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)

    domain_url = result.stdout.strip()
    if not domain_url:
        print(f"  FAILED: ConfigMap key DOMAIN_URL not found or empty")
        sys.exit(1)

    cmd2 = [
        "kubectl", "get", "cm", "-n", "sunbird", "player-env",
        "-ojsonpath={.data.SUNBIRD_SESSION_SECRET}"
    ]
    result2 = subprocess.run(cmd2, capture_output=True, text=True)
    if result2.returncode != 0:
        print(f"  FAILED: {result2.stderr.strip()}")
        sys.exit(1)

    session_secret = result2.stdout.strip()
    if not session_secret:
        print(f"  FAILED: ConfigMap key SUNBIRD_SESSION_SECRET not found or empty")
        sys.exit(1)

    client_secret = f"lms{session_secret}"
    print(f"  DOMAIN_URL: {domain_url}")
    return domain_url, client_secret


def step_2_get_user_token(domain_url, client_secret):
    """Request admin user token using password grant."""
    print("\n[Step 2/6] Requesting admin user token from Keycloak (password grant)...")

    if not ADMIN_USERNAME or not ADMIN_PASSWORD:
        print(f"  FAILED: ADMIN_USERNAME or ADMIN_PASSWORD not set")
        sys.exit(1)

    token_url = f"{domain_url}/auth/realms/{KEYCLOAK_REALM}/protocol/openid-connect/token"

    cmd = [
        "curl", "-s", "-X", "POST", token_url,
        "-H", "Content-Type: application/x-www-form-urlencoded",
        "-d", f"client_id={KEYCLOAK_CLIENT_ID}&client_secret={client_secret}&grant_type=password&username={ADMIN_USERNAME}&password={ADMIN_PASSWORD}"
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)

    try:
        token_resp = json.loads(result.stdout)
        if "error" in token_resp:
            print(f"  FAILED: {token_resp.get('error_description', token_resp.get('error'))}")
            sys.exit(1)

        refresh_token = token_resp.get("refresh_token")
        if not refresh_token:
            print(f"  FAILED: No refresh_token in response")
            sys.exit(1)

        print(f"  Refresh token obtained successfully")
        return refresh_token
    except json.JSONDecodeError:
        print(f"  FAILED: Invalid JSON response: {result.stdout[:200]}")
        sys.exit(1)


def step_3_get_sunbird_access_token(domain_url, refresh_token):
    """Exchange refresh token at Sunbird /auth/v1/refresh/token."""
    print("\n[Step 3/6] Exchanging refresh token at Sunbird /auth/v1/refresh/token...")

    refresh_url = f"{domain_url}/auth/v1/refresh/token"

    cmd = [
        "curl", "-s", "-X", "POST", refresh_url,
        "-H", "Content-Type: application/x-www-form-urlencoded",
        "-d", f"refresh_token={refresh_token}"
    ]

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)

    try:
        refresh_resp = json.loads(result.stdout)
        if refresh_resp.get("params", {}).get("status") != "successful":
            err = refresh_resp.get("params", {}).get("err")
            errmsg = refresh_resp.get("params", {}).get("errmsg")
            print(f"  FAILED: {err} - {errmsg}")
            sys.exit(1)

        access_token = refresh_resp.get("result", {}).get("access_token")
        if not access_token:
            print(f"  FAILED: No access_token in result")
            sys.exit(1)

        print(f"  Sunbird access token obtained successfully")
        return access_token
    except json.JSONDecodeError:
        print(f"  FAILED: Invalid JSON response: {result.stdout[:200]}")
        sys.exit(1)


def step_4_export_enrollments():
    """Export user enrollments (userid, courseid, batchid) from YugabyteDB."""
    print("\n[Step 4/6] Exporting user enrollments from YugabyteDB...")
    print(f"  Source: {KEYSPACE}.{TABLE}  (pod: {YB_POD}/{YB_NAMESPACE})")

    copy_cmd = (
        f"COPY {KEYSPACE}.{TABLE} (userid, courseid, batchid) "
        f"TO '{REMOTE_CSV}' WITH HEADER=false AND PAGESIZE=5000;"
    )
    result = yb_exec(["ycqlsh", "-e", copy_cmd])
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)

    summary = result.stdout.strip().splitlines()
    for line in summary[-3:]:
        if line.strip():
            print(f"  {line.strip()}")
    print("  Done.")


def step_5_read_enrollments():
    """Read enrollments from CSV inside YugabyteDB pod."""
    print("\n[Step 5/6] Reading exported enrollments...")
    result = yb_exec(["cat", REMOTE_CSV])
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        sys.exit(1)

    raw = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    print(f"  Enrollment records read: {len(raw)}")

    enrollments = []
    for line in raw:
        parts = line.split(",")
        if len(parts) >= 3:
            enrollments.append({
                "userid": parts[0].strip(),
                "courseid": parts[1].strip(),
                "batchid": parts[2].strip(),
            })

    print(f"  Parsed enrollments: {len(enrollments)}")
    return enrollments


def step_6_trigger_activity_api(token, enrollments):
    """Call activity/agg API for each enrollment on lern-service."""
    url_base = f"http://{LERN_SERVICE_HOST}:{LERN_SERVICE_PORT}/v1/activity/agg"
    total = len(enrollments)

    print(f"\n[Step 6/6] Triggering activity sync for {total} enrollments")
    print(f"  Endpoint : POST {url_base}")
    print(f"  Delay    : {ACTIVITY_API_DELAY_SECONDS}s between calls")
    print(f"  DRY_RUN  : {DRY_RUN}")

    if DRY_RUN:
        print("  [DRY_RUN] Skipping API calls. Showing first 5 targets:")
        for enr in enrollments[:5]:
            print(f"    would POST {url_base} with userid={enr['userid']}, courseid={enr['courseid']}, batchid={enr['batchid']}")
        return 0, 0, []

    ok = 0
    failed = 0
    failures = []

    for idx, enr in enumerate(enrollments, start=1):
        payload = json.dumps({
            "request": {
                "userId": enr["userid"],
                "courseId": enr["courseid"],
                "batchId": enr["batchid"],
            }
        })

        try:
            result = subprocess.run(
                [
                    "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                    "--max-time", str(ACTIVITY_API_TIMEOUT_SECONDS),
                    "-X", "POST", url_base,
                    "-H", "Content-Type: application/json",
                    "-H", f"x-authenticated-user-token: {token}",
                    "-d", payload,
                ],
                capture_output=True, text=True, timeout=ACTIVITY_API_TIMEOUT_SECONDS + 10,
            )
            status = result.stdout.strip() or "000"
        except subprocess.TimeoutExpired:
            status = "TIMEOUT"

        if status.startswith("2"):
            ok += 1
        else:
            failed += 1
            failures.append((enr["userid"], enr["courseid"], enr["batchid"], status))
            print(f"  [{idx}/{total}] {enr['userid'][:8]}.../{enr['courseid'][:8]}... -> HTTP {status}")

        if idx % PROGRESS_EVERY == 0:
            print(f"  Progress: {idx}/{total}  (OK: {ok}, FAILED: {failed})")

        if ACTIVITY_API_DELAY_SECONDS > 0:
            time.sleep(ACTIVITY_API_DELAY_SECONDS)

    return ok, failed, failures


def main():
    start = datetime.now()
    print("=" * 70)
    print(" Migration: User Course Progress Sync")
    print("=" * 70)
    print(f"  YB_POD                      : {YB_POD}")
    print(f"  YB_NAMESPACE                : {YB_NAMESPACE}")
    print(f"  KEYSPACE.TABLE              : {KEYSPACE}.{TABLE}")
    print(f"  KEYCLOAK_REALM              : {KEYCLOAK_REALM}")
    print(f"  KEYCLOAK_CLIENT_ID          : {KEYCLOAK_CLIENT_ID}")
    print(f"  ADMIN_USERNAME              : {ADMIN_USERNAME}")
    print(f"  LERN_SERVICE_HOST           : {LERN_SERVICE_HOST}")
    print(f"  LERN_SERVICE_PORT           : {LERN_SERVICE_PORT}")
    print(f"  ACTIVITY_API_DELAY_SECONDS  : {ACTIVITY_API_DELAY_SECONDS}")
    print(f"  DRY_RUN                     : {DRY_RUN}")
    print("=" * 70)

    disable_enrollment_filter()

    try:
        domain_url, client_secret = step_1_get_config_from_configmap()
        refresh_token = step_2_get_user_token(domain_url, client_secret)
        access_token = step_3_get_sunbird_access_token(domain_url, refresh_token)
        step_4_export_enrollments()
        enrollments = step_5_read_enrollments()

        if not enrollments:
            print("\nNo enrollments to process. Exiting.")
            enable_enrollment_filter()
            return

        ok, failed, failures = step_6_trigger_activity_api(access_token, enrollments)

        duration = (datetime.now() - start).total_seconds()
        print("\n" + "=" * 70)
        print(" Migration complete")
        print("=" * 70)
        print(f"  Total enrollments : {len(enrollments)}")
        print(f"  API OK            : {ok}")
        print(f"  API FAILED        : {failed}")
        print(f"  Duration          : {duration:.1f}s")
        print("=" * 70)

        enable_enrollment_filter()

        if failures:
            print("\nFirst 20 failures:")
            for userid, courseid, batchid, status in failures[:20]:
                print(f"  {userid[:8]}.../{courseid[:8]}.../{batchid[:8]}...  ->  HTTP {status}")
            sys.exit(1)
    except Exception as e:
        print(f"\nERROR: {e}")
        enable_enrollment_filter()
        raise


if __name__ == "__main__":
    main()
