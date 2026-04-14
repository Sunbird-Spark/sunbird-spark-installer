# Migration Guide: ED Installer 8.1.0 → Sunbird Spark Installer

---

## Part 1 — Infrastructure Migration (Terraform → OpenTofu)

ED Installer 8.1.0 used **Terraform** for cloud infrastructure provisioning. Spark Installer migrates to **OpenTofu**, which is a drop-in open-source fork of Terraform with the same module structure.

### What Changed

| Aspect | ED Installer (Terraform) | Spark Installer (OpenTofu) |
|--------|--------------------------|----------------------------|
| Tool | Terraform | OpenTofu |
| AKS Identity | Service Principal | System-Assigned Managed Identity |
| Provider version | Strict pinning (`~> 4.0.1`) | Flexible (`~> 4.0`) |
| Cloud support | Azure, GCP | Azure, GCP |

### Steps

1. Clone the Spark Installer repo and navigate to `opentofu/azure` or `opentofu/gcp`
2. Fill in `global-values.yaml` with your environment values
3. Run OpenTofu to provision infrastructure — it will create AKS/GKE, networking, storage, and generate `global-cloud-values.yaml`
4. No Terraform state migration is needed — this is a fresh infrastructure provisioning

> **Note:** The OpenTofu modules cover the same resources as the old Terraform modules: cluster (AKS/GKE), network, storage, keys, and output file generation.

---

## Part 2 — Service Migration

### Pre-requisites

- Existing ED Installer 8.1.0 running on the cluster
- New cluster created using Spark Installer (do not run Postman collection yet)
- Access to both clusters (`kubectl`)
- Spark Installer repo cloned

### Step 1 — Take Database Backups from Old Cluster

Take full dumps of all three databases from the existing ED Installer cluster:

- Cassandra
- Neo4j
- PostgreSQL

Verify backup files are complete and stored safely before proceeding.

### Step 2 — Update Domain and Blob URL in Dumps

Before restoring, update the old cluster's domain and blob storage URL in the dumps to match the new cluster:

- Replace old cluster domain with new cluster domain
- Replace old blob storage URL with new cluster's blob storage URL

This ensures all form data and content references point to the correct new cluster after migration.

### Step 3 — Deploy Spark Installer Building Blocks on New Cluster

Deploy `edbb` first — it contains YugabyteDB, JanusGraph, new Player, and all YCQL/YSQL schema changes. Then deploy `learnbb`, `knowledgebb`, and `obsrvbb`.

> **Note:** The new `edbb` does not include Cassandra, Neo4j, or PostgreSQL. When `edbb` is deployed, these old database pods are automatically removed from the cluster.

Wait for all pods to reach `Running` state before proceeding to database migrations.

YugabyteDB exposes:

- **YCQL** on port `9042` — Cassandra-compatible API
- **YSQL** on port `5433` — PostgreSQL-compatible API

### Step 4 — Run Cassandra → YugabyteDB (YCQL) Migrations

Migration scripts are available in `scripts/sunbird-yugabyte-migrations/`. Run migrations for each module:

- **sunbird-lern** — covers LMS, UserOrg, Groups, Notifications
- **sunbird-knowlg** — covers Content, Dial, Hierarchy
- **sunbird-inquiry** — covers Assessment, Questions

**Keyspaces created:**

| Module | Keyspaces |
|--------|-----------|
| sunbird-lern | `sunbird`, `sunbird_courses`, `sunbird_groups`, `sunbird_notifications`, `sunbird_programs` |
| sunbird-knowlg | `{ENV}_category_store`, `{ENV}_content_store`, `{ENV}_hierarchy_store`, `{ENV}_dialcode_store` |
| sunbird-inquiry | `{ENV}_hierarchy_store`, `{ENV}_question_store` |

### Step 5 — Migrate Neo4j → JanusGraph

JanusGraph replaces Neo4j and runs on top of YugabyteDB (YCQL). Migration scripts are available in `scripts/janusgraph/migration/`.

- Copy migration scripts into the JanusGraph pod
- Import data from Neo4j into JanusGraph
- Verify vertex and edge counts match the original Neo4j data

### Step 6 — Service Consolidation

The following services are replaced by consolidated services in Spark Installer:

| Stop (ED Installer) | Start (Spark Installer) |
|--------------------|------------------------|
| `lms` + `userorg` + `notification` | `lern-service` |
| `content` + `learning` | `knowlg-service` |

### Post-Migration Verification

- Verify all pods are in `Running` state
- Verify YugabyteDB keyspaces are created correctly
- Verify JanusGraph vertex and edge counts match Neo4j data

---

> **Note:** Always take a full database backup before starting migration. Run and validate in a staging environment before applying to production.
