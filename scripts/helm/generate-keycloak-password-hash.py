#!/usr/bin/env python3
"""
Generate Keycloak-compatible pbkdf2-sha256 password hash.
Use the output to update the admin password directly in YugabyteDB/PostgreSQL.

Usage:
    python3 generate-keycloak-password-hash.py

Then run in YugabyteDB:
    UPDATE credential
    SET secret_data = '<secret_data output>',
        credential_data = '<credential_data output>'
    WHERE type = 'password'
    AND user_id = (SELECT id FROM user_entity WHERE username = 'admin' AND realm_id = 'master');
"""

import hashlib
import base64
import os
import json

def generate_hash(password, iterations=27500):
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

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        password = sys.argv[1]
    else:
        password = input("Enter new admin password: ")
    secret_data, credential_data = generate_hash(password)

    print("\n--- Copy these values into your SQL UPDATE ---\n")
    print(f"secret_data:\n{secret_data}\n")
    print(f"credential_data:\n{credential_data}\n")
    print("--- SQL ---")
    print(f"""
UPDATE credential
SET secret_data = '{secret_data}',
    credential_data = '{credential_data}'
WHERE type = 'password'
AND user_id = (SELECT id FROM user_entity WHERE username = 'admin' AND realm_id = 'master');
""")

