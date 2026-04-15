# Migration Guide

Guide for migrating data from the old cluster to the new Sunbird cluster.

---

## Prerequisites

Before running any migration, expose the following services as **LoadBalancer** in the **old cluster**:

| Service | Port |
|---------|------|
| Cassandra | 9042 |
| PostgreSQL | 5432 |
| Neo4j | 7687 |
| Elasticsearch | 9200 |

```bash
kubectl patch svc <service-name> -n sunbird -p '{"spec": {"type": "LoadBalancer"}}'
```

Fill in the external IPs and passwords in `db-migration/values.yaml` before running.

---

## Migration Order

| Step | Job | What it does |
|------|-----|--------------|
| 1 | **postgres** | Dumps PostgreSQL DBs (keycloak, registry) from old cluster and restores into YugabyteDB |
| 2 | **keycloak** | Updates Keycloak admin password hash and client secrets in YugabyteDB |
| 3 | **cassandra** | Migrates Cassandra keyspaces to YugabyteDB (YCQL) |
| 4 | **neo4j** | Migrates Neo4j graph data to JanusGraph |
| 5 | **elasticsearch** | Migrates Elasticsearch indices from old to new cluster |
| 6 | **createdat** | Backfills missing `createdat` field in YugabyteDB and syncs users to Elasticsearch |

---

## How to Run

**Step 1** — Fill in values in `db-migration/values.yaml`:

```yaml
cassandra:
  host: ""        # External IP of old Cassandra

neo4j:
  host: ""        # External IP of old Neo4j
  password: ""

postgres:
  host: ""        # External IP of old PostgreSQL
  password: ""

keycloak:
  password: ""    # New Keycloak admin password
  newSecret: ""   # New client secret suffix

elasticsearchMigration:
  oldEsHost: ""   # URL of old Elasticsearch (e.g. http://1.2.3.4:9200)
```

**Step 2** — Enable one job at a time, then deploy:

```bash
# Example: run postgres migration
# Set jobs.postgres.enabled: true in values.yaml

helm upgrade --install db-migration ./migration/db-migration -n sunbird
```

**Step 3** — Watch job logs:

```bash
kubectl logs -n sunbird -l type=<job-type> --follow
# e.g. type=postgres, keycloak, cassandra, neo4j, elasticsearch, createdat
```

**Step 4** — Disable the job, enable the next one, repeat.

---

## Notes

- All jobs are **idempotent** — safe to re-run
- Enable only **one job at a time**
- ES migration uses **elasticdump** (direct HTTP)
- Neo4j migration exports CSV → runs Groovy import script inside JanusGraph pod via `kubectl exec`

---


