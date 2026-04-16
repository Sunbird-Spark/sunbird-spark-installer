# Data Migration Guide
## Release 8.1.0 → Sunbird Spark

This guide covers migrating an existing Sunbird installation from Release 8.1.0 to the new Sunbird Spark cluster.

**What changes in Spark:**
- YugabyteDB replaces both Cassandra and PostgreSQL
- JanusGraph replaces Neo4j
- Elasticsearch moves to a new cluster inside Spark

---

## Before You Begin

- Take a Velero backup of the Release 8.1.0 cluster before doing anything else.
- The Release 8.1.0 cluster must remain running and network-accessible throughout the entire migration. Do not shut it down until the Spark cluster is fully stable and all migrations are verified.
- All migration jobs are disabled by default in `values.yaml`. Enable each job individually, only when you are ready to run it.
- Jobs are idempotent — if a job fails partway through, it is safe to re-run from the beginning.
- Logs are retained for 7 days after a job finishes.
- Never run more than one migration job at the same time. Parallel jobs risk resource conflicts and data loss.

---

## Architecture Overview

| Component | Release 8.1.0 | Sunbird Spark |
|-----------|---------------|---------------|
| YCQL Database | Apache Cassandra | YugabyteDB (YCQL) |
| YSQL Database | PostgreSQL | YugabyteDB (YSQL) |
| Graph Database | Neo4j | JanusGraph |
| Search | Elasticsearch | Elasticsearch |

---

## Step 1 — Expose Release 8.1.0 Cluster Services

The Spark cluster needs to reach the Release 8.1.0 databases during migration. Expose each database service as a LoadBalancer using the following command:

```bash
kubectl patch svc <service-name> -n <namespace> \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

Repeat for each of these services:

| Service | Namespace | Port |
|---------|-----------|------|
| Cassandra | sunbird | 9042 |
| PostgreSQL | sunbird | 5432 |
| Neo4j | sunbird | 7687 |
| Elasticsearch | sunbird | 9200 |

After patching, note the external IP assigned to each service. You will need these IPs in Step 3.

---

## Step 2 — Set Up Spark Cluster Infrastructure

**Clone the installer**
```bash
git clone https://github.com/Sunbird-Spark/sunbird-spark-installer.git
cd sunbird-spark-installer
git checkout develop
```

**Reuse existing Azure resources**

The Spark cluster reuses the existing Release 8.1.0 Azure resource group, storage account, and blob containers. You do not need to create new ones.

In `global-cloud-values.yaml`, set the existing storage account name and container names.

In `global-values.yaml`, set the resource group and disable the storage module:
```yaml
global:
  resource_group_name: "<existing-resource-group>"
  skip_storage_module: true
```

**Create infrastructure and install databases**

Create the cluster infrastructure. Do not deploy application services yet.

Install only these three databases and wait for all three to be healthy before proceeding:
- YugabyteDB
- Elasticsearch
- JanusGraph

---

## Step 3 — Configure Source Hosts

Open `migration/db-migration/values.yaml` and fill in the external IPs from Step 1.

**PostgreSQL**
```yaml
postgres:
  host: "<release-8.1.0-postgresql-ip>"
  port: 5432
  username: "postgres"
  password: "<postgres-password>"
  databases:
    - keycloak
    - registry
```

**Cassandra**
```yaml
cassandra:
  host: "<release-8.1.0-cassandra-ip>"
  port: 9042
```

**Neo4j**
```yaml
neo4j:
  host: "<release-8.1.0-neo4j-ip>"
  port: 7687
  username: "neo4j"
  password: "<neo4j-password>"
```

**Keycloak**
```yaml
keycloak:
  password: "<new-keycloak-admin-password>"
  newSecret: "<new-client-secret-suffix>"
```

**Elasticsearch**
```yaml
elasticsearchMigration:
  oldEsHost: "http://<release-8.1.0-elasticsearch-ip>:9200"
  newEsHost: "http://elasticsearch.sunbird.svc.cluster.local:9200"
```

---

## Step 4 — Run Migrations in Order

Run one job at a time. Verify data after each job before enabling the next.

The deploy command is the same for every job:
```bash
helm upgrade --install db-migration ./migration/db-migration \
  -n sunbird \
  -f ./migration/db-migration/values.yaml
```

Check job status and logs:
```bash
kubectl get jobs -n sunbird
kubectl logs -n sunbird -l app=migration -f
```

---

### 4.1 PostgreSQL → YugabyteDB

Migrates the `keycloak` and `registry` databases to YugabyteDB (YSQL).

```yaml
jobs:
  postgres:
    enabled: true
```

Confirm both databases are accessible in YugabyteDB before continuing.

---

### 4.2 Keycloak → YugabyteDB

Updates the Keycloak admin password hash and all client secrets in YugabyteDB.

```yaml
jobs:
  keycloak:
    enabled: true
```

Confirm the Keycloak admin password and client secrets are updated before continuing.

---

### 4.3 Cassandra → YugabyteDB

Migrates all Cassandra keyspaces to YugabyteDB (YCQL).

Keyspaces migrated:
- sunbird
- sunbird_courses
- sb_content_store
- sb_hierarchy_store
- sb_dialcode_store
- sb_question_store
- sunbird_notifications
- sb_category_store
- dialcodes
- *(and others defined in `values.yaml`)*

```yaml
jobs:
  cassandra:
    enabled: true
```

Confirm all keyspaces are present and accessible in YugabyteDB before continuing.

---

### 4.4 Neo4j → JanusGraph

Migrates all graph nodes and relationships to JanusGraph. The migration runs in three stages:
1. Exports Neo4j data to CSV files
2. Copies the CSV files into the JanusGraph pod
3. Imports the data via a Gremlin script

```yaml
jobs:
  neo4j:
    enabled: true
```

Confirm node and edge counts in JanusGraph match the source Neo4j data before continuing.

---

### 4.5 Elasticsearch → Elasticsearch

Migrates all indices from the Release 8.1.0 cluster to the new Spark cluster using the Elasticsearch reindex API.

> Before running this step, add `reindex.remote.whitelist` to `elasticsearch.yml` in the learnbb Helm values. Without this, the reindex API cannot reach the Release 8.1.0 cluster.

```yaml
jobs:
  elasticsearch:
    enabled: true
```

Confirm all indices and document counts match between Release 8.1.0 and the new Spark Elasticsearch cluster.

---

## Step 5 — Add User createdat Field

This is a separate operation, not part of the main migration sequence. Run it after all Step 4 migrations are complete and verified.

This job adds and backfills the `createdat` field in both Elasticsearch and YugabyteDB from existing user timestamp data.

```yaml
jobs:
  addUserCreatedatField:
    enabled: true
```

---

## Step 6 — Generate Hierarchy Relations

Run this after the createdat backfill is complete. This job strips the `.img` suffix from `content_hierarchy` identifiers in YugabyteDB and triggers the knowlg-service hierarchy update-relation API for each unique identifier.

```yaml
jobs:
  generateHierarchyRelations:
    enabled: true
```

Confirm all hierarchy identifiers are updated before proceeding to post-migration steps.

---

## Step 7 — Post-Migration Steps

Complete these steps after all database migrations are done and verified.

### Update the Encryption Key

Open `helmcharts/learnbb/charts/lern/configs/env.yaml` and update `sunbird_encryption_key` with the value from the Release 8.1.0 cluster's userorg service environment:

```yaml
sunbird_encryption_key: "<release-8.1.0-random-string>"
```

> This key must exactly match the value from Release 8.1.0. A mismatch will cause decryption failures across services.

---

### Redeploy All Bundles

Redeploy all bundles in this exact order. Confirm each bundle is healthy before starting the next:

```
monitoring → edbb → learnbb → knowledgebb → obsrvbb → inquirybb → additional
```

---

### Map DNS to Domain

Get the external IP of the Spark ingress:
```bash
kubectl get svc nginx-public-ingress -n sunbird \
  -ojsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Create or update your DNS A record to point your domain to this IP. Wait for DNS propagation before running the next step.

---

### Generate Postman Environment and Run Spark Forms

Once DNS is live, run these two commands in order:
```bash
bash install.sh generate_postman_env
bash install.sh create_client_forms
```

Migration is complete once all Spark new forms have been successfully applied.

---

## Step 8 — Upload Content Assets to Blob

Upload the latest content assets to the Azure Blob Storage container.

Before creating a tag:
- Update the required secrets and variables in GitHub repository settings.
- Ensure you are on the latest branch.
- Create the tag from the latest branch.
- Use the same tag name across all repositories.

Run in the following order — creating a tag in each repository triggers the GitHub Actions workflow to upload the build artifacts to Blob Storage:

| Order | Repository |
|-------|------------|
| 1 | [sunbird-content-player](https://github.com/Sunbird-Knowlg/sunbird-content-player) |
| 2 | [sunbird-content-plugins](https://github.com/Sunbird-Knowlg/sunbird-content-plugins) |
| 3 | [sunbird-content-editor](https://github.com/Sunbird-Knowlg/sunbird-content-editor) |
| 4 | [sunbird-generic-editor](https://github.com/Sunbird-Knowlg/sunbird-generic-editor) |

Verify each upload is complete before creating the next tag.

---

## Monitoring & Logs

Stream live logs for any running migration job:
```bash
kubectl logs -n sunbird -l app=migration -f
```

Check the status of all migration jobs:
```bash
kubectl get jobs -n sunbird
```

Log retention settings in `values.yaml`:
```yaml
job:
  namespace: sunbird
  backoffLimit: 3                  # retries before a job is marked failed
  ttlSecondsAfterFinished: 604800  # clean up after 7 days
```

---

## Important Notes

- Enable only **one job at a time** in `values.yaml`.
- All jobs are **idempotent** — safe to re-run if a job fails.
- Elasticsearch migration uses elasticdump (direct HTTP — no Azure storage keys required).
- Neo4j migration exports CSV files and imports them into JanusGraph via `kubectl exec`.
- Do not shut down the Release 8.1.0 cluster until the Spark cluster is fully stable and verified.
