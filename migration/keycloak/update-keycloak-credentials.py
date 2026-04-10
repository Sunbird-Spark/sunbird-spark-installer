#!/usr/bin/env python3
"""
Generate Keycloak-compatible pbkdf2-sha256 password hash and update YugabyteDB.

Steps:
  1. Generate pbkdf2-sha256 password hash
  2. Update credential table in YugabyteDB (keycloak DB)
  3. Take new client secret as input and update client table

Usage:
    python3 generate-keycloak-password-hash.py

Optional env vars:
    KC_USERNAME        (default: admin)
    KC_PASSWORD        (default: prompted)
    KC_REALM_ID        (default: prompted)
    KC_OLD_SECRET      (old client secret to replace)
    YB_HOST            (default: yb-tserver-service)
    YB_PORT            (default: 5433)
    YB_USER            (default: yugabyte)
    YB_PASSWORD        (default: yugabyte)
    YB_DB              (default: keycloak)
"""

import hashlib
import base64
import os
import json
import sys
import subprocess


# ========== CONFIGURATION — Update these values before running ==========
KC_USERNAME       = "admin"                                   # Keycloak username (in master realm)
KC_PASSWORD       = "j1NSFEv3XvZrF80Q"                        # New Keycloak admin password
KC_NEW_SECRET     = "m3C64zZXGU63D3Bd"                        # New client secret suffix
YB_HOST           = "yb-tserver-service"                      # YugabyteDB host
YB_PORT           = "5433"                                    # YugabyteDB YSQL port
YB_USER           = "yugabyte"                                # YugabyteDB username
YB_PASSWORD       = "yugabyte"                                # YugabyteDB password
YB_DB             = "keycloak"                                # Database name


def generate_hash(password, iterations=27500):
    """Generate pbkdf2-sha256 hash for Keycloak."""
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac('sha256', password.encode('utf-8'), salt, iterations)

    secret_data = json.dumps({
        "value": base64.b64encode(dk).decode('utf-8'),
        "salt": base64.b64encode(salt).decode('utf-8'),
        "additionalParameters": {}
    })

    credential_data = json.dumps({
        "hashIterations": iterations,
        "algorithm": "pbkdf2-sha256",
        "additionalParameters": {}
    })

    return secret_data, credential_data



def ysql_query(sql):
    """Execute SQL and return stdout."""
    cmd = [
        "kubectl", "exec", "-n", "sunbird", "yb-tserver-0", "--",
        "ysqlsh", "-h", YB_HOST, "-p", YB_PORT,
        "-U", YB_USER, "-d", YB_DB,
        "-t", "-c", sql
    ]
    env = os.environ.copy()
    env["PGPASSWORD"] = YB_PASSWORD
    result = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def fetch_old_secret():
    """Fetch the common suffix from existing client secrets in YugabyteDB.
    Looks for a client with the longest secret to extract the suffix."""
    result = ysql_query("SELECT secret FROM client WHERE secret IS NOT NULL AND secret != '' ORDER BY LENGTH(secret) DESC LIMIT 1;")
    if result:
        secret = result.strip()
        # Extract suffix — last 16 characters
        suffix = secret[-16:]
        print(f"  Fetched existing client secret suffix: {suffix}")
        return suffix
    return None


def ysql_exec(sql):
    """Execute SQL against YugabyteDB YSQL."""
    cmd = [
        "kubectl", "exec", "-n", "sunbird", "yb-tserver-0", "--",
        "ysqlsh", "-h", YB_HOST, "-p", YB_PORT,
        "-U", YB_USER, "-d", YB_DB,
        "-c", sql
    ]
    env = os.environ.copy()
    env["PGPASSWORD"] = YB_PASSWORD
    result = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr.strip()}")
        return False
    print(f"  {result.stdout.strip()}")
    return True


def main():
    print("=" * 50)
    print(" Keycloak Password & Client Secret Update")
    print("=" * 50)

    # Get values from config
    password = KC_PASSWORD
    new_secret_input = KC_NEW_SECRET

    if not password:
        print("ERROR: Set KC_PASSWORD in the CONFIGURATION section.")
        sys.exit(1)

    print(f"\n  Username:  {KC_USERNAME}")
    print(f"  Realm:     master (password) / sunbird (clients)")
    print(f"  YB Host:   {YB_HOST}:{YB_PORT}/{YB_DB}")
    print("=" * 50)

    # Step 1 — Generate password hash
    print("\n[Step 1/3] Generating password hash...")
    secret_data, credential_data = generate_hash(password)
    print("  Done.")

    # Step 2 — Update credential in YugabyteDB
    print("\n[Step 2/3] Updating credential in YugabyteDB...")
    sql_update_password = (
        f"UPDATE credential "
        f"SET secret_data = $${secret_data}$$, "
        f"credential_data = $${credential_data}$$ "
        f"WHERE type = 'password' "
        f"AND user_id = (SELECT id FROM user_entity WHERE username = '{KC_USERNAME}' AND realm_id = (SELECT id FROM realm WHERE name = 'master'));"
    )
    print(f"  SQL: UPDATE credential SET secret_data=..., credential_data=... WHERE username='{KC_USERNAME}'")
    if not ysql_exec(sql_update_password):
        print("  FAILED to update password.")
        sys.exit(1)
    print(f"  Password updated for user '{KC_USERNAME}' in master realm.")

    # Step 3 — Update suffix of all client secrets
    if new_secret_input:
        print("\n[Step 3/3] Fetching existing client secret from YugabyteDB...")
        # Fix any clients that were wrongly set to just the new secret (no prefix)
        ysql_exec(
            f"UPDATE client SET secret = client_id || '{new_secret_input}' "
            f"WHERE secret = '{new_secret_input}';"
        )
        old_secret_input = fetch_old_secret()
        if not old_secret_input:
            print("  FAILED to fetch existing client secret. Skipping.")
        else:
            print("\n  Updating client secret suffix in YugabyteDB...")
            # Get count of clients to be updated
            count_result = ysql_query(f"SELECT COUNT(*) FROM client WHERE secret LIKE '%{old_secret_input}%';")
            client_count = count_result.strip() if count_result else "unknown"

            print(f"  Old secret: {old_secret_input}")
            print(f"  New secret: {new_secret_input}")
            print(f"  Clients to update: {client_count}")
            sql_update_secret = (
                f"UPDATE client "
                f"SET secret = REPLACE(secret, '{old_secret_input}', '{new_secret_input}') "
                f"WHERE secret LIKE '%{old_secret_input}%';"
            )
            if not ysql_exec(sql_update_secret):
                print("  FAILED to update client secret.")
                sys.exit(1)
            print(f"  {client_count} clients updated — old suffix '{old_secret_input}' replaced with '{new_secret_input}'")
            print(f"\n  NOTE: Update your helm values with new client secret: {new_secret_input}")
    else:
        print("\n[Step 3/3] Skipping client secret update (KC_NEW_SECRET not set).")

    print("\n" + "=" * 50)
    print(" Done!")
    print("=" * 50)
    print("\nRestart Keycloak to pick up changes:")
    print("  kubectl rollout restart deployment keycloak -n sunbird")


if __name__ == "__main__":
    main()

