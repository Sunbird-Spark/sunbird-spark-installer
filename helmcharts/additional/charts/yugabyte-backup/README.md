# yugabyte-backup

Automated daily backup of YugabyteDB (YSQL + YCQL) to cloud storage.
Runs as a Kubernetes CronJob. Disabled by default.

## Enable

In `global-values.yaml`:
```yaml
yugabyte-backup:
  enabled: true
  schedule: "30 11 * * 5"    # weekly, Friday 5:00 PM IST
  retentionDays: "56"        # ~8 weekly backups; final count TBD
```

Then deploy the `additional` building block:
```bash
./install.sh install_component additional
```

## Auth Modes

Cloud storage auth is driven by `global.cloud_storage_auth_type`, shared with every
other chart in this repo (flink, cert, lern, knowlg, velero, secor, nlwebflink):

| Value | Behavior |
|---|---|
| `"OIDC"` | Workload identity — no key needed. This is what Terraform auto-generates for Azure (`global-cloud-values.yaml`). Requires the pod's `azure.workload.identity/use: "true"` label + the federated SA (handled automatically by this chart). |
| anything else (unset, `"access_key"`, etc.) | Key-based — set `global.cloud_storage_secret_key` (and `cloud_storage_access_key` for the account/bucket name) yourself. This is the only path for GCP today (Terraform always populates `cloud_storage_secret_key` there and never sets `cloud_storage_auth_type`), and the fallback for Azure environments without workload identity set up. |

If you don't have OIDC/workload identity configured, just leave `cloud_storage_auth_type`
unset (or set it to anything other than `"OIDC"`) and provide `cloud_storage_secret_key` —
the chart will create a Secret and wire up key-based auth automatically.

## Backup Output

Backups are stored in the private cloud storage container/bucket under:
```
yugabyte-backups/
├── ysql/<db-name>/<timestamp>.sql.gz         # plain SQL, DROP/CREATE included, gzipped
│   e.g. ysql/keycloak/2026-07-27_170000.sql.gz
└── ycql/<keyspace-name>/<timestamp>.tar.gz   # schema.cql + one <table>.csv per table, tarred + gzipped
    e.g. ycql/janusgraph/2026-07-27_170000.tar.gz
```

Full blob URL format (Azure): `https://<storage_account>.blob.core.windows.net/<private_container>/yugabyte-backups/<ysql|ycql>/<db-or-keyspace-name>/<timestamp>.<sql.gz|tar.gz>`

Example, as actually observed on `ed-dev`:
```
https://eddevda72f12a.blob.core.windows.net/ed-dev-private-0c422ccdbf/yugabyte-backups/ycql/content_store/2026-07-27_071355.tar.gz
```

In-scope YSQL databases (8): `keycloak`, `registry`, `quartz`, `enc-keys`, `kong`, `portal`, `superset`, `sunbird`

In-scope YCQL keyspaces (~15, auto-discovered): all non-system keyspaces, including `janusgraph` (JanusGraph's storage backend).

---

## Restore

> Always preview the restore commands before running them against production.

### YSQL Restore (PostgreSQL)

**Step 1 — Retrieve the backup file from blob storage**

```bash
# Azure
az storage blob download \
  --account-name <storage_account> \
  --container-name <private_container> \
  --name yugabyte-backups/ysql/keycloak/<timestamp>.sql.gz \
  --file /tmp/keycloak.sql.gz \
  --auth-mode login

# GCP
gsutil cp gs://<bucket>/yugabyte-backups/ysql/keycloak/<timestamp>.sql.gz /tmp/

# AWS
aws s3 cp s3://<bucket>/yugabyte-backups/ysql/keycloak/<timestamp>.sql.gz /tmp/
```

**Step 2 — Decompress**

```bash
gunzip /tmp/keycloak.sql.gz
```

**Step 3 — Apply**

The dump was generated with `--clean --if-exists --create`, so it already contains
`DROP DATABASE IF EXISTS` / `CREATE DATABASE` / `\connect` statements — safe to re-run,
no separate drop/create step needed. Connect to any existing maintenance database
(here, YugabyteDB's default `yugabyte` db):

```bash
psql -h yb-tserver-service -p 5433 -U yugabyte -f /tmp/keycloak.sql
```

Repeat for each database: `registry`, `quartz`, `enc-keys`, `kong`, `portal`, `superset`, `sunbird`.

---

### YCQL Restore (Cassandra)

**Step 1 — Retrieve the backup file from blob storage**

```bash
# Azure
az storage blob download \
  --account-name <storage_account> \
  --container-name <private_container> \
  --name yugabyte-backups/ycql/janusgraph/<timestamp>.tar.gz \
  --file /tmp/janusgraph.tar.gz \
  --auth-mode login

# GCP
gsutil cp gs://<bucket>/yugabyte-backups/ycql/janusgraph/<timestamp>.tar.gz /tmp/

# AWS
aws s3 cp s3://<bucket>/yugabyte-backups/ycql/janusgraph/<timestamp>.tar.gz /tmp/
```

**Step 2 — Unpack** (contains `schema.cql` + one `<table>.csv` per table)

```bash
tar -xzf /tmp/janusgraph.tar.gz -C /tmp/
```

**Step 3 — Restore schema**

```bash
ycqlsh yb-tserver-service 9042 -f /tmp/janusgraph/schema.cql
```

**Step 4 — Restore data per table**

```bash
ycqlsh yb-tserver-service 9042 \
  -e "COPY janusgraph.<table> FROM '/tmp/janusgraph/<table>.csv' WITH HEADER=true;"
```

Repeat for each table in the keyspace, and for each keyspace being restored.

---

## List Available Backups

```bash
# Azure
az storage blob list \
  --account-name <storage_account> \
  --container-name <private_container> \
  --prefix "yugabyte-backups/" \
  --auth-mode login \
  --query "[].name" -o table

# GCP
gsutil ls gs://<bucket>/yugabyte-backups/

# AWS
aws s3 ls s3://<bucket>/yugabyte-backups/ --recursive
```

## Check Backup Job Status

```bash
kubectl get cronjobs -n sunbird | grep yugabyte-backup
kubectl get jobs -n sunbird | grep yugabyte-backup
kubectl logs -n sunbird job/<job-name>
```
