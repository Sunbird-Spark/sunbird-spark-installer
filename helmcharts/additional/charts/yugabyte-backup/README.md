# yugabyte-backup

Automated daily backup of YugabyteDB (YSQL + YCQL) to cloud storage.
Runs as a Kubernetes CronJob. Disabled by default.

## Enable

In `global-values.yaml`:
```yaml
yugabyte-backup:
  enabled: true
  schedule: "0 2 * * *"    # daily at 2 AM UTC
  retentionDays: "7"
```

Then deploy the `additional` building block:
```bash
./install.sh install_component additional
```

## Backup Output

Backups are stored in the private cloud storage container/bucket under:
```
yugabyte-backups/
├── ysql/<date>/
│   ├── keycloak.dump
│   ├── quartz.dump
│   ├── enc-keys.dump
│   ├── registry.dump
│   └── sunbird.dump
└── ycql/<date>/
    ├── <keyspace>/schema.cql
    └── <keyspace>/<table>.csv
```

---

## Restore

### YSQL Restore (PostgreSQL)

**Step 1 — Download backup from cloud storage**

```bash
# Azure
az storage blob download \
  --account-name <storage_account> \
  --container-name <private_container> \
  --name yugabyte-backups/ysql/<date>/keycloak.dump \
  --file /restore/keycloak.dump \
  --auth-mode login

# GCP
gsutil cp gs://<bucket>/yugabyte-backups/ysql/<date>/keycloak.dump /restore/

# AWS
aws s3 cp s3://<bucket>/yugabyte-backups/ysql/<date>/keycloak.dump /restore/
```

**Step 2 — Drop and recreate database (if restoring to existing cluster)**

```bash
psql -h yb-tserver-service -p 5433 -U yugabyte -c "DROP DATABASE IF EXISTS keycloak;"
psql -h yb-tserver-service -p 5433 -U yugabyte -c "CREATE DATABASE keycloak;"
```

**Step 3 — Restore**

```bash
PGPASSWORD=yugabyte pg_restore \
  -h yb-tserver-service \
  -p 5433 \
  -U yugabyte \
  -d keycloak \
  -F c \
  /restore/keycloak.dump
```

Repeat for each database: `quartz`, `enc-keys`, `registry`, `sunbird`.

---

### YCQL Restore (Cassandra)

**Step 1 — Download backup from cloud storage**

```bash
# Azure
az storage blob download-batch \
  --account-name <storage_account> \
  --source <private_container> \
  --pattern "yugabyte-backups/ycql/<date>/*" \
  --destination /restore/ \
  --auth-mode login

# GCP
gsutil -m cp -r gs://<bucket>/yugabyte-backups/ycql/<date>/ /restore/

# AWS
aws s3 cp s3://<bucket>/yugabyte-backups/ycql/<date>/ /restore/ --recursive
```

**Step 2 — Restore schema**

```bash
ycqlsh yb-tserver-service 9042 -f /restore/<keyspace>/schema.cql
```

**Step 3 — Restore data per table**

```bash
ycqlsh yb-tserver-service 9042 \
  -e "COPY <keyspace>.<table> FROM '/restore/<keyspace>/<table>.csv' WITH HEADER=true;"
```

Repeat for each table in each keyspace.

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
