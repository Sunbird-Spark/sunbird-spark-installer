# DB Migration

---

## Step 1 — Expose Services as LoadBalancer in Old Cluster

```bash
kubectl patch svc cassandra -n sunbird -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc postgresql -n sunbird -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc neo4j -n sunbird -p '{"spec": {"type": "LoadBalancer"}}'
kubectl patch svc elasticsearch -n sunbird -p '{"spec": {"type": "LoadBalancer"}}'
```

Get external IPs:
```bash
kubectl get svc -n sunbird | grep LoadBalancer
```

Update IPs in `values.yaml`.

---

## Step 2 — Run Migrations (in order)

```bash
# 1. PostgreSQL
# Enable: jobs.postgres.enabled: true
helm upgrade --install db-migration ./migration/db-migration -n sunbird

# 2. Keycloak credentials
python3 migration/keycloak/update-keycloak-credentials.py

# 3. Cassandra
# Enable: jobs.cassandra.enabled: true
helm upgrade --install db-migration ./migration/db-migration -n sunbird

# 4. Neo4j → JanusGraph
# Enable: jobs.neo4j.enabled: true
helm upgrade --install db-migration ./migration/db-migration -n sunbird

# 5. Elasticsearch (elasticdump — no Azure keys needed)
# Enable: jobs.elasticsearch.enabled: true
helm upgrade --install db-migration ./migration/db-migration -n sunbird

# 6. createdat backfill
# Enable: jobs.createdat.enabled: true
helm upgrade --install db-migration ./migration/db-migration -n sunbird
```

> Enable only one job at a time in `values.yaml`.
