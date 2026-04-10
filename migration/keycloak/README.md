# Keycloak Credentials Update

This script updates the Keycloak admin password and client secrets directly in YugabyteDB.

---

## What it does

1. **Generates** a `pbkdf2-sha256` password hash for the Keycloak admin user
2. **Updates** the `credential` table in YugabyteDB (`master` realm)
3. **Fetches** the existing client secret from YugabyteDB automatically
4. **Updates** all client secrets in the `client` table (`sunbird` realm)

---

## Prerequisites

- `kubectl` configured and pointing to the correct cluster
- `yb-tserver-0` pod running in `sunbird` namespace
- Python 3.x

---

## Configuration

Edit the `CONFIGURATION` section at the top of `update-keycloak-credentials.py` before running:

```python
KC_USERNAME   = "admin"              # Keycloak username (default: admin)
KC_PASSWORD   = "Admin@123"          # New Keycloak admin password
KC_NEW_SECRET = "m3C64zZXGU63D3Bd"  # New client secret suffix
YB_HOST       = "yb-tserver-service" # YugabyteDB host
YB_PORT       = "5433"               # YugabyteDB YSQL port
YB_USER       = "yugabyte"           # YugabyteDB username
YB_PASSWORD   = "yugabyte"           # YugabyteDB password
YB_DB         = "keycloak"           # Database name
```

---

## How to run

```bash
python3 update-keycloak-credentials.py
```

---

## Example Output

```
==================================================
 Keycloak Password & Client Secret Update
==================================================

  Username:  admin
  Realm:     master (password) / sunbird (clients)
  YB Host:   yb-tserver-service:5433/keycloak
==================================================

[Step 1/3] Generating password hash...
  Done.

[Step 2/3] Updating credential in YugabyteDB...
  SQL: UPDATE credential SET secret_data=..., credential_data=... WHERE username='admin'
  UPDATE 1
  Password updated for user 'admin' in master realm.

[Step 3/3] Fetching existing client secret from YugabyteDB...
  Fetched existing client secret: VI9lAOcXeeuzKJA5

  Updating client secret suffix in YugabyteDB...
  Old secret: VI9lAOcXeeuzKJA5
  New secret: m3C64zZXGU63D3Bd
  Clients to update: 12
  UPDATE 12
  12 clients updated — old suffix 'VI9lAOcXeeuzKJA5' replaced with 'm3C64zZXGU63D3Bd'

  NOTE: Update your helm values with new client secret: m3C64zZXGU63D3Bd

==================================================
 Done!
==================================================

Restart Keycloak to pick up changes:
  kubectl rollout restart deployment keycloak -n sunbird
```

---

## After running

Restart Keycloak to pick up the changes:

```bash
kubectl rollout restart deployment keycloak -n sunbird
```

Update the client secret in your helm values file wherever it is referenced.
