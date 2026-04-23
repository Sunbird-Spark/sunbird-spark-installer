# Cross-Cloud Database Migration

This directory contains Helm charts and scripts for migrating databases from Sunbird ED 8.1.0 to Sunbird Spark across any cloud providers.

## Architecture

```
SOURCE CLUSTER                    OBJECT STORAGE                 TARGET CLUSTER
(Sunbird ED 8.1.0)               (Blob / S3 / GCS)             (Sunbird Spark)

+-----------------+               +----------------+             +------------------+
|                 |               |                |             |                  |
| PostgreSQL    --|-- dump ------>|                |-- restore ->| YugabyteDB YSQL  |
|                 |               |                |             |                  |
| Cassandra     --|-- export --->|   Artifacts     |-- restore ->| YugabyteDB YCQL  |
|                 |               |   stored here   |             |                  |
| Neo4j         --|-- export --->|                |-- restore ->| JanusGraph       |
|                 |               |                |             |                  |
| Elasticsearch --|-- snapshot ->|                |-- restore ->| Elasticsearch    |
|                 |               |                |             |                  |
+-----------------+               +----------------+             +------------------+

      PHASE 1                       HANDOFF POINT                    PHASE 2
   (run on source)                                                (run on target)
```

## Helm Charts

### 1. database-export (Phase 1)
- **Purpose**: Export databases from source cluster and upload to object storage
- **When to run**: On source cluster (Sunbird ED 8.1.0)
- **What it does**:
  - PostgreSQL: `pg_dump` → upload `.sql` files
  - Cassandra: Export to CSV → gzip → upload
  - Neo4j: Export nodes/relationships → CSV → gzip → upload  
  - Elasticsearch: Create snapshot in object storage

### 2. database-import (Phase 2)
- **Purpose**: Pull artifacts from object storage and restore to target databases
- **When to run**: On target cluster (Sunbird Spark)
- **What it does**:
  - PostgreSQL: Pull `.sql` → restore to YugabyteDB YSQL
  - Cassandra: Pull CSV → create schema → load data to YugabyteDB YCQL
  - Neo4j: Pull CSV → import to JanusGraph
  - Elasticsearch: Restore snapshot
  - Post-migration: Keycloak credentials, createdat backfill, hierarchy fixes

## Usage

### Azure to Azure (Same Cloud)
```bash
# Phase 1: Export from source
helm install database-export ./database-export \
  --namespace migration

# Phase 2: Import to target  
helm install database-import ./database-import \
  --namespace migration
```

### Azure to GCP (Cross-Cloud)
```bash
# Phase 1: Export from Azure source
helm install database-export ./database-export \
  --namespace migration

# Sync artifacts between clouds
rclone sync azure:edsandboxda72f12a/database-backup gcs:target-bucket/database-backup

# Phase 2: Import to GCP target
helm install database-import ./database-import \
  --namespace migration
```

## Supported Cloud Providers

- **Azure**: Azure Blob Storage
- **GCP**: Google Cloud Storage  
- **AWS**: S3
- **On-prem**: MinIO or any S3-compatible storage

## Validation

Each export records row/document counts. Each import compares counts after restore. Mismatches are logged for review.

## Failure Handling

All jobs are idempotent and safe to re-run. Kubernetes handles automatic retries up to 3 times.
