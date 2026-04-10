# DB Migration Helm Chart

Helm chart to run all database migrations from old cluster to new cluster.

---

## Migrations Available

| Job | Description | Source → Target |
|-----|-------------|-----------------|
| `cassandra` | Cassandra keyspaces data dump | Cassandra → YugabyteDB YCQL |
| `postgres` | PostgreSQL databases dump/restore | PostgreSQL → YugabyteDB YSQL |
| `neo4j` | Graph data migration | Neo4j → JanusGraph |
| `createdat` | Backfill `createdat` field for users | YugabyteDB → Elasticsearch |
| `elasticsearch` | Index data migration | Old ES → New ES |

---

## Configuration

Edit `values.yaml` before running:

### 1. Enable/Disable Jobs

```yaml
jobs:
  cassandra:
    enabled: false      # Set true to run Cassandra migration
  postgres:
    enabled: false      # Set true to run PostgreSQL migration
  neo4j:
    enabled: false      # Set true to run Neo4j migration
  createdat:
    enabled: false      # Set true to run createdat backfill
  elasticsearch:
    enabled: true       # Set true to run Elasticsearch migration
```

### 2. Cassandra Source

```yaml
cassandra:
  host: "20.207.92.174"     # Old Cassandra IP
  port: 9042
  keyspaces:
    - sunbird
    - sunbird_courses
    - ...
```

### 3. Neo4j Source

```yaml
neo4j:
  host: "20.207.70.157"     # Old Neo4j IP
  port: 7687
  username: "neo4j"
  password: ""
```

### 4. PostgreSQL Source

```yaml
postgres:
  host: "20.204.200.23"     # Old PostgreSQL IP
  port: 5432
  databases:
    - keycloak
    - registry
  username: "postgres"
  password: "yourpassword"
```

### 5. Elasticsearch Migration

```yaml
elasticsearchMigration:
  oldEsHost: "http://20.219.175.25:9200"                          # Old ES IP
  newEsHost: "http://elasticsearch.sunbird.svc.cluster.local:9200" # New ES
  indices: ""        # Leave empty to migrate all indices
  batchSize: 1000
```

### 6. YugabyteDB Target

```yaml
yugabyte:
  host: "yb-tserver-service.sunbird.svc.cluster.local"
  port: 9042
  sqlPort: 5433
  username: "yugabyte"
  password: ""
```

---

## How to Run

### Run a specific migration (e.g. Elasticsearch only):

```bash
helm upgrade --install db-migration ./migration/db-migration \
  -n sunbird \
  --set jobs.elasticsearch.enabled=true
```

### Run using values.yaml:

```bash
helm upgrade --install db-migration ./migration/db-migration \
  -n sunbird \
  -f ./migration/db-migration/values.yaml
```

### Watch logs:

```bash
kubectl logs -n sunbird -l app=migration -f
```

---

## Example Output

### Neo4j → JanusGraph

```
================================================================================
Neo4j → JanusGraph Migration (Python)
================================================================================
  Source: Neo4j  20.207.70.157:7687
  Target: JanusGraph pod (namespace=sunbird, label=app.kubernetes.io/name=janusgraph)
  Connected to Neo4j at bolt://20.207.70.157:7687
  Discovered 1 node labels: ['domain']
  Discovered 2 relationship types: ['hasSequenceMember', 'associatedTo']

[1/3] Exporting Neo4j data to CSV
  Exported 1165 nodes to /tmp/nodes.csv
  Exported 226 relationships to /tmp/relationships.csv

[2/3] Importing into JanusGraph via kubectl exec
  Found JanusGraph pod: janusgraph-5c58c54796-pxnqr
  Copied /tmp/nodes.csv → pod:/tmp/nodes.csv
  Copied /tmp/relationships.csv → pod:/tmp/relationships.csv

  --- Running import_data.groovy ---
  [gremlin] Importing Nodes...
  [gremlin] Vertices: 1161
  [gremlin] Edges: 452

================================================================================
MIGRATION COMPLETE
  Nodes exported   : 1165
  Edges exported   : 226
  Import status    : SUCCESS ✓
  Verify status    : SUCCESS ✓
  Duration         : 136.51s (2.3m)
================================================================================
```

### Elasticsearch Migration

```
==================================================
 Elasticsearch Migration: Old → New
==================================================
  OLD_ES_HOST:  http://20.219.175.25:9200
  NEW_ES_HOST:  http://elasticsearch.sunbird.svc.cluster.local:9200
  BATCH_SIZE:   1000
  INDICES:      all

Checking connectivity...
  Old ES: elastic — yellow
  New ES: elastic — yellow

Found 66 indices to migrate

[1/66] Migrating: userv3
  Reindexing 'userv3' (139 docs)... total=139, created=0, updated=139, failures=0
  Verified: old=139, new=139 ✓
...
==================================================
 Migration Summary
  Total:   66
  Success: 66
  Failed:  0
  All indices migrated successfully!
==================================================
```

### createdat Backfill

```
==============================
 Migration: createdat backfill
==============================
  ES_HOST:   http://elasticsearch:9200
  YB_POD:    yb-tserver-0
  KEYSPACE:  sunbird
  BATCH_SIZE: 500

[Step 1/6] Updating ES mapping... Done.
[Step 2/6] Altering YugaByte table... Done.
[Step 3/6] Exporting user data from YugaByte... Done.
[Step 4/6] Generating and executing backfill statements... Done.
[Step 5/6] Verifying backfill...
  id          | createdat  | createddate
  abc-123     | 2025-07-30 | 2025-07-30 09:11:59
[Step 6/6] Triggering data sync for 92 users...
  Batch 1/1 (92 users)... OK
==============================
 Migration complete!
==============================
```

---

## Notes

- Only **one job should be enabled at a time** to avoid resource conflicts
- Jobs are idempotent — safe to re-run
- Logs are retained for 7 days (`ttlSecondsAfterFinished: 604800`)
- For Elasticsearch migration, `reindex.remote.whitelist` must be set in `elasticsearch.yml` — add `extraConfig` to learnbb helm values
