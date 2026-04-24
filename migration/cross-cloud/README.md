# Cross-Cloud Database Migration

Helm charts to migrate databases from **Sunbird ED 8.1.0** to **Sunbird Spark** across any cloud provider.

---

## Architecture

```
SOURCE CLUSTER                    OBJECT STORAGE                 TARGET CLUSTER
(Sunbird ED 8.1.0)               (Blob / S3 / GCS)             (Sunbird Spark)

+-----------------+               +----------------+             +------------------+
| PostgreSQL    --|-- pg_dump --> |                |-- restore ->| YugabyteDB YSQL  |
| Cassandra     --|-- CSV ------> |   Artifacts    |-- restore ->| YugabyteDB YCQL  |
| Neo4j         --|-- CSV ------> |                |-- restore ->| JanusGraph       |
| Elasticsearch --|-- snapshot -> |                |-- restore ->| Elasticsearch    |
+-----------------+               +----------------+             +------------------+

      PHASE 1                       HANDOFF POINT                    PHASE 2
   (database-export)                                               (database-import)
```

---

## Charts

| Chart              | Phase | Where it runs   | Purpose                                          |
|--------------------|-------|-----------------|--------------------------------------------------|
| `database-export`  | 1     | Source cluster  | Dump databases, push to object storage           |
| `database-import`  | 2     | Target cluster  | Pull artifacts, restore to Sunbird Spark + fixes |

Both charts are chart-version **1.0.0**, appVersion **1.0.0**, Helm v3, Kubernetes ≥ 1.24.

---

## Namespace strategy

Two distinct namespaces are involved:

| Namespace               | Set via                          | Contains                                             | Created by chart? |
|-------------------------|----------------------------------|------------------------------------------------------|-------------------|
| **Release namespace**   | `helm install -n <ns>`           | Jobs, SA, ConfigMap, Secret (from this chart)        | No — use `--create-namespace` or pre-create |
| **DB pod namespace**    | `source.namespace` / `target.namespace` in values.yaml | Existing DB pods (sunbird). Role + RoleBinding created here for kubectl-exec | No — must pre-exist |

**Rules:**
- Release namespace is your choice: `sunbird`, `migration`, or anything else. Jobs run there.
- DB pod namespace **must already exist** with the running DB pods. Chart does not create/modify it beyond adding a `Role` + `RoleBinding` for `pod-exec`.
- Release namespace CAN equal DB pod namespace (install chart into `sunbird`) — works fine.
- Cross-namespace case (release=`migration`, DB pods in `sunbird`) — RoleBinding spans both, SA in release ns has permission to exec into DB ns pods.

**Install in `migration` ns (recommended — isolates migration jobs):**
```bash
helm install database-export ./database-export \
  -n migration --create-namespace \
  --set source.namespace=sunbird \
  -f values.yaml
```

**Install in `sunbird` ns (co-located with DB pods):**
```bash
helm install database-export ./database-export \
  -n sunbird \
  --set source.namespace=sunbird \
  -f values.yaml
```

Same pattern for `database-import` with `target.namespace`.

---

## Prerequisites

- `helm` v3.12+
- `kubectl` with access to **both** source and target clusters (separate contexts recommended)
- Object storage bucket/container reachable from **both** clusters (or use `rclone` between clouds)
- For cross-cloud: `rclone` CLI to sync between source & target storage
- Source DB pods reachable from the source cluster namespace
- Target DB pods reachable from the target cluster namespace
- RBAC in each DB namespace — the charts create `pod-exec` Role + RoleBinding automatically

---

## Quick start — same cloud (Azure → Azure)

```bash
# --- Phase 1: Source cluster ---
kubectl config use-context <source-context>
kubectl create namespace migration

helm install database-export ./database-export \
  --namespace migration \
  -f my-source-values.yaml

# wait for jobs to complete
kubectl get jobs -n migration -w

# --- Phase 2: Target cluster ---
kubectl config use-context <target-context>
kubectl create namespace migration

helm install database-import ./database-import \
  --namespace migration \
  -f my-target-values.yaml

kubectl get jobs -n migration -w
```

---

## Quick start — cross-cloud (Azure → GCP)

```bash
# Phase 1: export on Azure
helm install database-export ./database-export -n migration -f azure-source.yaml

# Sync artifacts between clouds
rclone sync azure:databasebackup/ gcs:target-bucket/databasebackup/ --progress

# Phase 2: import on GCP
helm install database-import ./database-import -n migration -f gcp-target.yaml
```

---

## What you MUST update before installing

### `database-export/values.yaml`

| Key                                           | Required | Example                                        |
|-----------------------------------------------|----------|------------------------------------------------|
| `source.cloud`                                | yes      | `azure` / `gcp` / `aws` / `onprem`             |
| `source.namespace`                            | yes      | namespace where source DB pods live            |
| `source.container` / `source.bucket`          | yes      | destination bucket/container for artifacts     |
| `source.storageAccount` + `source.accessKey`  | azure    | Azure storage account + access key             |
| `source.bucket` + `source.serviceAccountKey`  | gcp      | GCS bucket + SA key JSON                       |
| `source.s3Bucket` + `source.accessKeyId` + `source.secretAccessKey` + `source.region` | aws | S3 bucket + IAM creds |
| `source.useExistingSecrets`                   | yes      | `true` = read creds from cluster secrets       |
| `databases.<db>.enabled`                      | yes      | toggle each DB (pg, cassandra, neo4j, es)      |
| `databases.<db>.host` / `port`                | yes      | DB service DNS                                 |
| `databases.<db>.secretName`                   | cond.    | K8s secret with `username`/`password` keys     |
| `databases.<db>.username` / `password`        | cond.    | fallback creds when no `secretName`            |
| `databases.cassandra.podName` + `podNamespace`| yes      | source pod for `kubectl exec DESCRIBE`         |
| `databases.neo4j.podName` + `podNamespace`    | yes      | source Neo4j pod                               |
| `databases.elasticsearch.podName`             | yes      | source ES master pod (default `elasticsearch-master-0`) |
| `databases.cassandra.keyspaces`               | yes      | list of keyspaces to export                    |

### `database-import/values.yaml`

| Key                                                      | Required | Example                                  |
|----------------------------------------------------------|----------|------------------------------------------|
| `target.cloud`                                           | yes      | `azure` / `gcp` / `aws` / `onprem`       |
| `target.namespace`                                       | yes      | namespace where target DB pods live      |
| `target.container` / `target.bucket`                     | yes      | source bucket holding exported artifacts |
| `target.*` cloud creds                                   | yes      | same pattern as export chart             |
| `target.*_path`                                          | yes      | path prefixes (must match source output) |
| `databases.yugabytedb.enabled` / `host` / `port`         | yes      | YSQL target                              |
| `databases.yugabytedb.databases[].username` / `password` | yes      | per-DB target creds                      |
| `databases.ycql.enabled` / `host` / `port`               | yes      | YCQL target                              |
| `databases.ycql.sourcePrefix` / `targetPrefix`           | opt.     | rename keyspaces on restore (e.g. `sb_`→`dv_`) |
| `databases.ycql.keyspaces`                               | yes      | keyspaces to restore                     |
| `databases.janusgraph.enabled` / `host` / `port`         | yes      | JanusGraph target                        |
| `databases.elasticsearch.enabled` / `host` / `port`      | yes      | ES target                                |
| `databases.elasticsearch.podName`                        | yes      | target ES master pod                     |
| `postMigration.keycloakCredentials.enabled`              | opt.     | rotate Keycloak client secrets           |
| `postMigration.keycloakCredentials.adminPassword`        | cond.    | Keycloak master-realm admin password     |
| `postMigration.keycloakCredentials.secretSuffix`         | cond.    | suffix appended to new secrets           |
| `postMigration.createdatBackfill.enabled`                | opt.     | backfill `createdat` column on user docs |
| `postMigration.hierarchyFix.enabled`                     | opt.     | call knowlg-service to fix hierarchy ids |
| `postMigration.hierarchyFix.knowlgServiceHost` / `Port`  | yes if enabled | service DNS + port                 |

---

## Execution order (helm hook weights)

**Export** (phase 1):
1. `postgres-export` (1)
2. `cassandra-export` (2)
3. `neo4j-export` (3)
4. `elasticsearch-snapshot` (4)

**Import** (phase 2):
1. `postgres-restore` (YSQL) (1)
2. `keycloak-credentials` (2)
3. `cassandra-restore` (YCQL) (3)
4. `janusgraph-restore` (4)
5. `elasticsearch-restore` (5)
6. `createdat-backfill` (6)
7. `hierarchy-fix` (7)

Only enabled steps run. Disabled steps are skipped.

---

## Supported cloud providers

| Provider | Storage         | Status |
|----------|-----------------|--------|
| Azure    | Blob Storage    | ✅     |
| GCP      | Cloud Storage   | ✅     |
| AWS      | S3              | ✅     |
| On-prem  | MinIO / S3-API  | ✅     |

---

## Monitoring

```bash
# watch jobs
kubectl get jobs -n migration -w

# stream all logs
kubectl logs -n migration -l app.kubernetes.io/instance=database-export -f --tail=200

# validation diffs
kubectl logs -n migration -l app.kubernetes.io/instance=database-import \
  | grep -E 'MISMATCH|VALIDATION|ERROR'
```

---

## Validation

Each export records row/document counts. Each import compares counts after restore.
- `validation.strictMode=false` (default) → log mismatches, continue
- `validation.strictMode=true` → fail the job on mismatch

---

## Failure handling

- Jobs are **idempotent** and safe to re-run (`helm upgrade`).
- Kubernetes retries failed jobs up to `jobs.backoffLimit` (default 10).
- Finished jobs auto-delete after `jobs.ttlSecondsAfterFinished` (default 3600s).
- Re-running `database-export` overwrites artifacts in blob storage.

---

## Troubleshooting

| Symptom                                  | Likely cause                                                 | Fix                                                    |
|------------------------------------------|--------------------------------------------------------------|--------------------------------------------------------|
| Job stuck with `Forbidden: pods/exec`    | `target.namespace` wrong — RBAC created in wrong namespace   | Set `target.namespace` to match source/target DB pods |
| `cassandra-restore` fails to install deps| Air-gapped cluster; `python:3.11` unreachable                | Override `databases.ycql.image` to a mirror           |
| `keycloak-credentials` job returns 401   | `adminPassword` wrong or master realm locked                 | Verify `postMigration.keycloakCredentials.adminPassword` |
| `hierarchy-fix` returns 404              | `knowlg-service` DNS wrong or service not deployed           | Update `postMigration.hierarchyFix.knowlgServiceHost` |
| ES restore `repository_verification_exception` | keystore creds missing on target ES pod                | Check `keystorePath` + re-add Azure credentials       |
| Helm install succeeds, no jobs run       | No DB has `enabled: true`                                    | Enable at least one database                          |

---

## Uninstall

```bash
helm uninstall database-export -n migration
helm uninstall database-import -n migration
```

Artifacts in blob storage are **not** deleted. Remove manually when migration is validated.
