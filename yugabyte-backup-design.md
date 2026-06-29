# YugabyteDB Backup & Restore Design

## Goal

Provide reliable, automatable backup and restore for YugabyteDB (both YSQL and YCQL interfaces) running in Sunbird-ED Kubernetes clusters, without depending on Velero or persistent volume snapshots.

---

## Scope

| Interface | Protocol | Port | What it stores |
|-----------|----------|------|----------------|
| YSQL | PostgreSQL-compatible | 5433 | Keycloak, Quartz, enc-keys, registry, sunbird portal data |
| YCQL | Cassandra-compatible | 9042 | Sunbird platform data, dialcodes, JanusGraph keyspaces |

Redis and OpenSearch are **excluded** — Redis is cache-only; OpenSearch indices can be rebuilt from YugabyteDB source data.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Kubernetes Cluster (daily 2 AM UTC, automated)     │
│                                                     │
│  CronJob: yugabyte-backup                           │
│    ├── YSQL (pg_dump per database)                  │
│    │     keycloak, quartz, enc-keys,                │
│    │     registry, sunbird                          │
│    │                                                │
│    └── YCQL (ycqlsh COPY TO per table + schema DDL) │
│          all non-system keyspaces                   │
└──────────────┬──────────────────────────────────────┘
               │ upload via workload identity
               ▼
┌─────────────────────────────────────────────────────┐
│  Cloud Storage (private container/bucket)           │
│  yugabyte-backups/                                  │
│    ├── ysql/2026-06-29/keycloak.dump                │
│    ├── ysql/2026-06-29/sunbird.dump                 │
│    ├── ycql/2026-06-29/<keyspace>/schema.cql        │
│    └── ycql/2026-06-29/<keyspace>/<table>.csv       │
│                                                     │
│  Retention: 7 days (auto-deleted by backup job)     │
└─────────────────────────────────────────────────────┘

Restore: manual on-demand only
  ├── YSQL: download → pg_restore per database
  └── YCQL: download → ycqlsh COPY FROM per table
```

---

## Backup

### YSQL Backup (pg_dump)

**Tool:** `pg_dump` (PostgreSQL client, works with YugabyteDB YSQL)

**Databases to back up:**
- `keycloak`
- `quartz`
- `enc-keys`
- `registry`
- `sunbird`

**Command per database:**
```bash
pg_dump \
  -h yb-tserver-service \
  -p 5433 \
  -U yugabyte \
  -F c \          # custom format (compressed, supports parallel restore)
  -d <database> \
  -f /backup/ysql/<database>.dump
```

**Cloud upload (Azure):**
```bash
az storage blob upload \
  --account-name <storage_account> \
  --container-name <private_container> \
  --name yugabyte-backups/ysql/<date>/<database>.dump \
  --file /backup/ysql/<database>.dump \
  --auth-mode login
```

**Cloud upload (GCP):**
```bash
gsutil cp /backup/ysql/<database>.dump \
  gs://<bucket>/yugabyte-backups/ysql/<date>/<database>.dump
```

---

### YCQL Backup (ycqlsh COPY TO)

**Tool:** `ycqlsh` (YugabyteDB's Cassandra shell, pre-installed in yb-tserver pods)

**Approach:** Export each table as CSV using `COPY TO`.

**Keyspaces to back up:** Discovered dynamically — all non-system keyspaces.

**Command per table:**
```bash
ycqlsh yb-tserver-service 9042 \
  -e "COPY <keyspace>.<table> TO '/backup/ycql/<keyspace>/<table>.csv' WITH HEADER=true;"
```

**Schema backup (DDL):**
```bash
ycqlsh yb-tserver-service 9042 \
  -e "DESCRIBE KEYSPACE <keyspace>;" > /backup/ycql/<keyspace>/schema.cql
```

**Cloud upload:** Same as YSQL (per file).

---

## Restore

### YSQL Restore

```bash
# 1. Download backup
az storage blob download \
  --account-name <storage_account> \
  --container-name <private_container> \
  --name yugabyte-backups/ysql/<date>/<database>.dump \
  --file /restore/<database>.dump \
  --auth-mode login

# 2. Drop and recreate database (if needed)
psql -h yb-tserver-service -p 5433 -U yugabyte -c "DROP DATABASE IF EXISTS <database>;"
psql -h yb-tserver-service -p 5433 -U yugabyte -c "CREATE DATABASE <database>;"

# 3. Restore
pg_restore \
  -h yb-tserver-service \
  -p 5433 \
  -U yugabyte \
  -d <database> \
  -F c \
  /restore/<database>.dump
```

### YCQL Restore

```bash
# 1. Download schema + CSV files
# 2. Recreate keyspace and tables from schema
ycqlsh yb-tserver-service 9042 -f /restore/ycql/<keyspace>/schema.cql

# 3. Load data per table
ycqlsh yb-tserver-service 9042 \
  -e "COPY <keyspace>.<table> FROM '/restore/ycql/<keyspace>/<table>.csv' WITH HEADER=true;"
```

---

## Implementation

### Kubernetes CronJob (fully automated)

- Runs automatically every day at 2 AM UTC (configurable)
- No manual intervention — fires on schedule, backs up, uploads, cleans old backups
- Docker image: custom image with `postgresql-client`, `ycqlsh`, `az CLI` / `gsutil`
- Workload identity / service account for cloud storage access — no credentials stored
- Retention: 7 days default, older backups auto-deleted at end of each run
- On failure: CronJob retries up to 3 times, Kubernetes marks job as failed (visible in `kubectl get cronjobs`)

### Helm Chart Location

```
helmcharts/additional/charts/yugabyte-backup/
  Chart.yaml
  values.yaml
  templates/
    cronjob.yaml
    configmap.yaml        # backup scripts
    serviceaccount.yaml
```

### `global-values.yaml` flags

```yaml
yugabyte_backup:
  enabled: true
  schedule: "0 2 * * *"              # daily at 2 AM UTC
  retention_days: 7
  # Auth mode — matches cloud_storage_auth_type used by other services
  # "workload_identity" = no keys needed (Azure OIDC / GCP WI / AWS IRSA)
  # "access_key" = explicit keys in Secret
  cloud_storage_auth_type: "workload_identity"
  # Required only when cloud_storage_auth_type: access_key
  # Azure: storage account name + access key
  # GCP: service account JSON (base64 encoded)
  # AWS: access key ID + secret + region
  storage_account: ""
  storage_key: ""
  storage_region: ""                 # AWS only
  ysql_databases:
    - keycloak
    - quartz
    - enc-keys
    - registry
    - sunbird
  # YCQL keyspaces: leave empty to auto-discover all non-system keyspaces
  ycql_keyspaces: []
```

---

## Docker Image

Custom image based on `ubuntu:22.04` with:
- `postgresql-client` (pg_dump, psql, pg_restore)
- `ycqlsh` (YugabyteDB CQL shell)
- `az` CLI (Azure upload)
- `gsutil` / `gcloud` CLI (GCP upload)
- `aws` CLI (AWS upload)
- Backup shell scripts (auto-selects tool based on `CLOUD_SERVICE` env var)

Built and pushed via `.github/workflows/build-push-images.yml`.

---

## Retention / Cleanup

On each backup run, after upload:
```bash
# Azure: delete blobs older than retention_days
az storage blob delete-batch \
  --account-name <storage_account> \
  --source <private_container> \
  --pattern "yugabyte-backups/*" \
  --if-unmodified-since <cutoff_date> \
  --auth-mode login
```

---

## Multi-Cloud Support

Cloud provider detected from `global.cloud_service_provider` in `global-values.yaml` (`azure` / `gcp` / `aws`). Upload tool and auth method selected automatically.

| Provider | Upload tool | Workload identity | Access key |
|---|---|---|---|
| `azure` | `az storage blob upload` | `--auth-mode login` (OIDC) | `--account-key $AZURE_KEY` |
| `gcp` | `gsutil cp` | GKE metadata server (IRSA equivalent) | `GOOGLE_APPLICATION_CREDENTIALS` JSON |
| `aws` | `aws s3 cp` | IRSA (IAM role for SA) | `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` |

---

## Authentication — Dual Mode

Controlled by `cloud_storage_auth_type` in `global-values.yaml` (same field used by other services):

### Mode 1: Workload Identity / Service Account (recommended)

No credentials stored. Cluster must have workload identity configured.

**Azure** — pod annotation from Helm:
```yaml
podAnnotations:
  azure.workload.identity/client-id: "{{ .Values.global.azure_client_id }}"
```
```bash
az storage blob upload --auth-mode login ...
```

**GCP** — ServiceAccount annotation from Helm:
```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: <gsa>@<project>.iam.gserviceaccount.com
```
```bash
gsutil cp ...   # uses GKE metadata server automatically
```

**AWS** — ServiceAccount annotation (IRSA) from Helm:
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account>:role/<role>
```
```bash
aws s3 cp ...   # uses IRSA token automatically
```

### Mode 2: Access Keys (fallback)

For environments without workload identity. Keys mounted from Kubernetes Secret.

| Provider | Env vars |
|---|---|
| `azure` | `AZURE_STORAGE_ACCOUNT`, `AZURE_KEY` |
| `gcp` | `GOOGLE_APPLICATION_CREDENTIALS` (path to SA JSON file) |
| `aws` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` |

When `cloud_storage_auth_type: access_key` → Helm creates Secret from provided values, mounts as env vars.
When `cloud_storage_auth_type: workload_identity` → Helm adds pod/SA annotations only, no Secret created.

