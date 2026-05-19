#!/usr/bin/env python3
"""
Generate Keycloak-compatible pbkdf2-sha256 password hash and update YugabyteDB.

Steps:
  1. Generate pbkdf2-sha256 password hash
  2. Update credential table in YugabyteDB (keycloak DB)
  3. Fetch old client secret suffix and replace with new one

Reads config from environment variables (injected by Helm).
"""

import hashlib
import base64
import os
import json
import sys
import psycopg2

# ========== CONFIG FROM ENV VARS (set via Helm values) ==========
KC_USERNAME   = os.environ.get("KC_USERNAME", "admin")
KC_PASSWORD   = os.environ.get("KC_PASSWORD", "")
KC_NEW_SECRET = os.environ.get("KC_NEW_SECRET", "")
YB_HOST       = os.environ.get("YB_HOST", "yb-tserver-service")
YB_PORT       = int(os.environ.get("YB_PORT", "5433"))
YB_USER       = os.environ.get("YB_USER", "yugabyte")
YB_PASSWORD   = os.environ.get("YB_PASSWORD", "yugabyte")
YB_DB         = os.environ.get("YB_DB", "keycloak")


def get_connection():
    return psycopg2.connect(
        host=YB_HOST,
        port=YB_PORT,
        user=YB_USER,
        password=YB_PASSWORD,
        dbname=YB_DB
    )


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


def fetch_old_secret(conn):
    """Fetch the common suffix from existing client secrets."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT secret FROM client WHERE secret IS NOT NULL AND secret != '' "
            "ORDER BY LENGTH(secret) DESC LIMIT 1;"
        )
        row = cur.fetchone()
        if row:
            suffix = row[0][-16:]
            print(f"  Fetched existing client secret suffix: {suffix}")
            return suffix
    return None


def main():
    print("=" * 50)
    print(" Keycloak Password & Client Secret Update")
    print("=" * 50)

    if not KC_PASSWORD:
        print("ERROR: KC_PASSWORD env var not set.")
        sys.exit(1)

    print(f"\n  Username : {KC_USERNAME}")
    print(f"  YB Host  : {YB_HOST}:{YB_PORT}/{YB_DB}")
    print("=" * 50)

    conn = get_connection()
    conn.autocommit = False

    try:
        # Step 1 — Generate password hash
        print("\n[Step 1/3] Generating password hash...")
        secret_data, credential_data = generate_hash(KC_PASSWORD)
        print("  Done.")

        # Step 2 — Update credential in YugabyteDB
        print("\n[Step 2/3] Updating credential in YugabyteDB...")
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE credential
                SET secret_data = %s, credential_data = %s
                WHERE type = 'password'
                AND user_id = (
                    SELECT id FROM user_entity
                    WHERE username = %s
                    AND realm_id = (SELECT id FROM realm WHERE name = 'master')
                );
                """,
                (secret_data, credential_data, KC_USERNAME)
            )
            print(f"  Rows updated: {cur.rowcount}")
        conn.commit()
        print(f"  Password updated for user '{KC_USERNAME}' in master realm.")

        # Step 3 — Update client secret suffix
        if KC_NEW_SECRET:
            print("\n[Step 3/3] Updating client secret suffix...")
            with conn.cursor() as cur:
                # Fix any clients wrongly set to just the new secret
                cur.execute(
                    "UPDATE client SET secret = client_id || %s WHERE secret = %s;",
                    (KC_NEW_SECRET, KC_NEW_SECRET)
                )
            conn.commit()

            old_suffix = fetch_old_secret(conn)
            if not old_suffix:
                print("  FAILED to fetch existing client secret. Skipping.")
            else:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT COUNT(*) FROM client WHERE secret LIKE %s;",
                        (f"%{old_suffix}%",)
                    )
                    count = cur.fetchone()[0]
                    print(f"  Old suffix : {old_suffix}")
                    print(f"  New suffix : {KC_NEW_SECRET}")
                    print(f"  Clients    : {count}")

                    cur.execute(
                        "UPDATE client SET secret = REPLACE(secret, %s, %s) WHERE secret LIKE %s;",
                        (old_suffix, KC_NEW_SECRET, f"%{old_suffix}%")
                    )
                    print(f"  Rows updated: {cur.rowcount}")
                conn.commit()
                print(f"  NOTE: Update helm values with new client secret: {KC_NEW_SECRET}")
        else:
            print("\n[Step 3/3] Skipping client secret update (KC_NEW_SECRET not set).")

    except Exception as e:
        conn.rollback()
        print(f"\nERROR: {e}")
        sys.exit(1)
    finally:
        conn.close()

    print("\n" + "=" * 50)
    print(" Done! Restart Keycloak to pick up changes.")
    print("=" * 50)


if __name__ == "__main__":
    main()
