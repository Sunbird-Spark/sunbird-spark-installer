# Data Migration Guide
## Release 8.1.0 → Sunbird Spark (Cross-Cloud)

This guide covers migrating Sunbird ED 8.1.0 data to a new Sunbird Spark cluster using the two-phase cross-cloud workflow under `migration/cross-cloud/`:

| Phase | Chart | Runs in | Purpose |
|---|---|---|---|
| 1 — Export | `migration/cross-cloud/database-export` | Source 8.1.0 cluster | Dumps source DBs to cloud object storage |
| 2 — Import | `migration/cross-cloud/database-import` | Target Spark cluster | Restores artifacts into Spark DBs + runs post-migration fixes |

**What changes in Spark:**
- YugabyteDB replaces both Cassandra and PostgreSQL
- JanusGraph replaces Neo4j
- Elasticsearch moves to a new cluster

---

## Before You Begin

- Take a Velero backup of the 8.1.0 cluster before starting.
- Keep the 8.1.0 cluster running .
- Every `enabled` flag in the chart `values.yaml` defaults to **false**. Toggle one DB at a time.
- Each job is idempotent — safe to re-run if it fails partway.
- Run **one migration job at a time**. Parallel jobs risk resource conflicts and data loss.
- Logs retained 7 days after job completion (`jobs.ttlSecondsAfterFinished`).

---

## Architecture Overview

| Component | 8.1.0 | Sunbird Spark |
|-----------|---------------|---------------|
| YCQL | Apache Cassandra | YugabyteDB (YCQL) |
| YSQL | PostgreSQL | YugabyteDB (YSQL) |
| Graph | Neo4j | JanusGraph |
| Search | Elasticsearch | Elasticsearch |

Cross-cloud transport = cloud object storage (Azure Blob / GCS / S3). Source pushes artifacts, target pulls. No direct network path between clusters needed.

---

# Phase 1 — Export from 8.1.0 cluster

## Step 1.1 — Configure export values

Open `migration/cross-cloud/database-export/values.yaml`.

Fill the `source` block for your cloud:

```yaml
source:
  cloud: "azure"                 # azure | gcp | aws | onprem
  namespace: "sunbird"           # ns where source DB pods live
  container: "databasebackup"    # bucket / blob container

  # Azure
  storageAccount: "<source-storage-account>"
  accessKey: "<source-storage-key>"   # or use MSI / workload identity

  # GCP
  bucket: ""
  projectId: ""
  serviceAccountKey: ""

  # AWS
  s3Bucket: ""
  accessKeyId: ""
  secretAccessKey: ""
  region: ""

  # Path prefixes inside container
  postgresql_path: "postgresql"
  cassandra_path: "cassandra"
  elasticsearch_path: "elasticsearch"
  neo4j_path: "neo4j"
```

`databases.<db>.host/port/username/password` are pre-set to in-cluster service names. Override only if non-default.

## Step 1.2 — Export DBs one by one

Enable exactly one `enabled: true` at a time. Deploy, wait for the Job to finish, verify the artifact landed in the container, then move to the next DB.

```bash
# PostgreSQL
helm upgrade --install database-export ./migration/cross-cloud/database-export \
  -n sunbird -f ./migration/cross-cloud/database-export/values.yaml \
  --set databases.postgresql.enabled=true

# Cassandra
helm upgrade --install database-export ./migration/cross-cloud/database-export \
  -n sunbird -f ./migration/cross-cloud/database-export/values.yaml \
  --set databases.cassandra.enabled=true

# Neo4j
helm upgrade --install database-export ./migration/cross-cloud/database-export \
  -n sunbird -f ./migration/cross-cloud/database-export/values.yaml \
  --set databases.neo4j.enabled=true

# Elasticsearch
helm upgrade --install database-export ./migration/cross-cloud/database-export \
  -n sunbird -f ./migration/cross-cloud/database-export/values.yaml \
  --set databases.elasticsearch.enabled=true
```

Recommended order: PostgreSQL → Cassandra → Neo4j → Elasticsearch.

Check job + logs:
```bash
kubectl get jobs -n sunbird
kubectl logs -n sunbird -l app=database-export -f
```

Verify each export by listing the corresponding path prefix in the storage container.

---

# Phase 2 — Set up Spark cluster infrastructure

Clone installer:
```bash
git clone https://github.com/Sunbird-Spark/sunbird-spark-installer.git
cd sunbird-spark-installer
git checkout develop
```

If you reuse the existing 8.1.0 Azure resource group / storage account, set them in `opentofu/<provider>/<env>/global-values.yaml` and `global-cloud-values.yaml`:

```yaml
global:
  resource_group_name: "<existing-resource-group>"
  skip_storage_module: true
```

Provision the cluster but **do not install application services yet**. Install only the data stores and wait until all three are healthy:
- YugabyteDB
- Elasticsearch
- JanusGraph

---

# Phase 3 — Import into Spark cluster

## Step 3.1 — Configure import values

Open `migration/cross-cloud/database-import/values.yaml`.

Fill the `target` block — same cloud/container that Phase 1 wrote to:

```yaml
target:
  cloud: "azure"
  namespace: "sunbird"
  container: "databasebackup"
  storageAccount: "<source-storage-account>"
  accessKey: "<source-storage-key>"
  postgresql_path: "postgresql"
  cassandra_path: "cassandra"
  elasticsearch_path: "cluster-1"   # default ES snapshot dir
  neo4j_path: "neo4j"
```

Spark DB endpoints under `databases.*` are pre-set to in-cluster service names.

**YCQL keyspace prefix rename (mandatory if `global.env` differs from 8.1.0 keyspace prefix):**
```yaml
ycql:
  sourcePrefix: "sb_"             # 8.1.0 keyspace prefix in source data
  targetPrefix: "dv_"             # MUST equal `global.env` + "_" from opentofu/<provider>/<env>/global-values.yaml
  truncateBeforeLoad: "true"
```
Knowlg/Lern read keyspaces as `{global.env}_content_store`. If `global.env: dv`, set `targetPrefix: "dv_"` so `sb_content_store` → `dv_content_store` at restore. Mismatch = services can't find keyspaces post-migration. Set both to `""` to disable rename when prefixes already match.

## Step 3.2 — Run imports one by one

Enable each DB flag in order, run, verify, then move on.

```bash
# 1. YSQL  (PostgreSQL → YugabyteDB YSQL)
--set databases.yugabytedb.enabled=true

# 2. Keycloak credentials  (run AFTER YSQL — rewrites admin password + rotates client secrets in migrated keycloak DB)
--set postMigration.keycloakCredentials.enabled=true

# 3. YCQL  (Cassandra → YugabyteDB YCQL)
--set databases.ycql.enabled=true

# 4. JanusGraph  (Neo4j → JanusGraph)
--set databases.janusgraph.enabled=true

# 5. Elasticsearch  (snapshot restore)
--set databases.elasticsearch.enabled=true

# 6. createdat backfill  (User.createdat in YB + ES)
--set postMigration.createdatBackfill.enabled=true
```

**Step 2 — keycloakCredentials values:**

```yaml
postMigration:
  keycloakCredentials:
    enabled: true
    adminPassword: "<from-global-values.yaml>"       # opentofu/<provider>/<env>/global-values.yaml → keycloak admin password
    secretSuffix: "<from-global-cloud-values.yaml>"  # opentofu/<provider>/<env>/global-cloud-values.yaml → random string used for rotated client secrets
```

This step is **not** part of the PostgreSQL data move (that's step 1 / YSQL). It runs after YSQL import to rewrite the Keycloak admin password hash + append `secretSuffix` to every client secret stored in the migrated `keycloak` DB, aligning credentials with the Spark cluster's chart values.

Deploy command (same for every step — toggle the flag, leave the rest false):
```bash
helm upgrade --install database-import ./migration/cross-cloud/database-import \
  -n sunbird -f ./migration/cross-cloud/database-import/values.yaml
```

Watch jobs:
```bash
kubectl get jobs -n sunbird
kubectl logs -n sunbird -l app=database-import -f
```

Verify after each step before enabling the next:
- YSQL: `\dt` in `keycloak` and `registry` databases via `ysqlsh`
- YCQL: `DESC KEYSPACES` in `ycqlsh` shows all migrated keyspaces (with target prefix if renamed)
- JanusGraph: `g.V().count()` and `g.E().count()` match Neo4j source totals
- Elasticsearch: `_cat/indices?v` shows all indices with expected doc counts

---

# Phase 4 — Bring up application services

After all DB imports verified, install the remaining bundles in order:

```
monitoring → edbb → learnbb → knowledgebb → obsrvbb → inquirybb → additional
```

Wait for each bundle to be healthy before starting the next.

---

# Phase 5 — Post-migration fix-ups

## Step 5.1 — Hierarchy fix

Strips `.img` suffix from `content_hierarchy` identifiers in YugabyteDB and triggers knowlg-service `update-relation` API for each unique identifier.

```bash
helm upgrade --install database-import ./migration/cross-cloud/database-import \
  -n sunbird -f ./migration/cross-cloud/database-import/values.yaml \
  --set postMigration.hierarchyFix.enabled=true
```

Config:
```yaml
postMigration:
  hierarchyFix:
    enabled: true
    ybPod: "yb-tserver-0"
    knowlgServiceHost: "knowlg-service.sunbird.svc.cluster.local"
    knowlgServicePort: 9000
    dryRun: false
```

## Step 5.2 — Keycloak realm diff

Applies Spark chart `realm.json` diffs onto the migrated Keycloak DB. Preserves all migrated users/sessions; only patches realm settings, client config, auth flows, required actions to match the chart.

```bash
helm upgrade --install database-import ./migration/cross-cloud/database-import \
  -n sunbird -f ./migration/cross-cloud/database-import/values.yaml \
  --set postMigration.keycloakRealmReconcile.enabled=true
```

Config:
```yaml
postMigration:
  keycloakRealmReconcile:
    enabled: true
    keycloakUrl: "http://keycloak.sunbird.svc.cluster.local:8080"
    realm: "sunbird"
    namespace: "sunbird"
    adminUser: "admin"
    adminPassword: "<keycloak-admin-password>"
    realmConfigMap: "keycloak"
    realmConfigMapKey: "realm.json"
```

---

# Phase 6 — DNS + Forms

## Step 6.1 — Map DNS

Get the Spark ingress IP:
```bash
kubectl get svc nginx-public-ingress -n sunbird \
  -ojsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Update the DNS A record to point your domain at this IP. Wait for propagation.

## Step 6.2 — Encryption key

Update `helmcharts/learnbb/charts/lern/configs/env.yaml`:
```yaml
sunbird_encryption_key: "<release-8.1.0-random-string>"
```

The value **must match** the 8.1.0 cluster's userorg-service `sunbird_encryption_key`. Mismatch = decryption failures across services. Redeploy `learnbb` after this change.

## Step 6.3 — Generate Postman env + run forms

Once DNS is live:
```bash
bash install.sh generate_postman_env
bash install.sh migrate_forms
```

`migrate_forms`:
- Runs System Settings APIs (privacyPolicyConfig, googleClientId)
- For each form in `3 - Forms`:
  - read=404 → create (env-substituted body)
  - read=200 → update (env-substituted body)
  - Skip-update list: `1 - Resource Create`, `2 - Resource Save`, `3 - Resource Review`, `7 - Assessment Filter`, `8 - Assessment Question save`, `10 - Textbook create`

Migration is complete once Spark forms apply cleanly.

---

# Monitoring & Logs

Stream live logs for any running migration job:
```bash
kubectl logs -n sunbird -l app=database-export -f
kubectl logs -n sunbird -l app=database-import -f
```

Check job status:
```bash
kubectl get jobs -n sunbird
```

Log retention in `values.yaml`:
```yaml
jobs:
  backoffLimit: 10                 # retries before failure
  ttlSecondsAfterFinished: 3600    # cleanup after job completes
```

---

# Important Notes

- **Enable only one `enabled: true` at a time** in `values.yaml`. Run, verify, then enable the next.
- **All jobs are idempotent** — re-runnable on failure.
- **Cross-cloud transport via object storage** — source/target clusters need no direct network reach.
- **YCQL prefix rename** lets you migrate `sb_*` keyspaces into `dv_*` (or any other prefix) without rewriting downstream service config.
- **Keep 8.1.0 cluster running** until Spark is fully verified — never shut it down mid-migration.
- **DB endpoints** in `databases.*` are pre-set to in-cluster service DNS names. Override only when those differ in your env.
