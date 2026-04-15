# DB Migration

Helm chart to migrate data from old cluster to new cluster.

---

## Prerequisites

Expose these services as **LoadBalancer** in the **old cluster** before running:

| Service | Port |
|---------|------|
| Cassandra | 9042 |
| PostgreSQL | 5432 |
| Neo4j | 7687 |
| Elasticsearch | 9200 |

```bash
kubectl patch svc <service-name> -n sunbird -p '{"spec": {"type": "LoadBalancer"}}'
```

Update the LoadBalancer IPs in `values.yaml` before running.

---

## Migration Order

| Step | Job | Enable in `values.yaml` |
|------|-----|---------|
| 1 | **postgres** | `jobs.postgres.enabled: true` |
| 2 | **keycloak** | `jobs.keycloak.enabled: true` |
| 3 | **cassandra** | `jobs.cassandra.enabled: true` |
| 4 | **neo4j** | `jobs.neo4j.enabled: true` |
| 5 | **elasticsearch** | `jobs.elasticsearch.enabled: true` |
| 6 | **createdat** | `jobs.createdat.enabled: true` |

Enable only one job at a time, then run from repo root:
```bash
helm upgrade --install db-migration ./migration/db-migration -n sunbird
```

---

## Notes

- ES migration uses **elasticdump** (direct HTTP, no Azure keys needed)
- Keycloak script updates admin password and all client secrets
- Jobs are idempotent — safe to re-run
