---

## Migration Script Execution Order


Export relationships:
```bash
bin/cypher-shell -u neo4j \
"MATCH (a)-[r]->(b) RETURN id(a) AS from_id, type(r) AS rel_type, id(b) AS to_id, properties(r) AS props" \
--format plain > /var/lib/neo4j/import/relationships.csv
```

> Note: `nodes.csv` and `relationships.csv` are Neo4j exports. Keep them in a safe local path before copying to the JanusGraph pod.

## 2. Prepare JanusGraph (Run in Kubernetes environment)

> **Note:** Schema initialization is now handled automatically by the Helm deployment job (`schemaInit.enabled: true` in values.yaml). Skip to step 3 after confirming the schema-init job has completed successfully.
>
> Check schema-init job status:
> ```bash
> kubectl get jobs -n sunbird | grep schema-init
> kubectl logs -n sunbird -l app=janusgraph,job=schema-init --tail=50
> ```

## 3. Copy Neo4j CSV data and migration scripts to the JanusGraph pod
After schema initialization completes, copy the CSV files and import/verify scripts:
```bash
kubectl cp nodes.csv sunbird/$JG_POD:/tmp/migration/nodes.csv
kubectl cp relationships.csv sunbird/$JG_POD:/tmp/migration/relationships.csv
kubectl cp import_data.groovy sunbird/$JG_POD:/tmp/import_data.groovy
kubectl cp verify_migration.groovy sunbird/$JG_POD:/tmp/verify_migration.groovy
```

If you prefer to copy everything in one archive:
```bash
tar -czf migration.tar.gz nodes.csv relationships.csv import_data.groovy verify_migration.groovy
kubectl cp migration.tar.gz sunbird/$JG_POD:/tmp/migration.tar.gz
kubectl exec -it -n sunbird $JG_POD -- tar -xzf /tmp/migration.tar.gz -C /tmp
```

## 4. Import data into JanusGraph

Run the import script inside JanusGraph:
```bash
kubectl exec -it -n sunbird $JG_POD -- /opt/bitnami/janusgraph/bin/gremlin.sh -e /tmp/import_data.groovy
```

## 5. Verify migration

Run the verification script:
```bash
kubectl exec -it -n sunbird $JG_POD -- /opt/bitnami/janusgraph/bin/gremlin.sh -e /tmp/verify_migration.groovy
```

Quick validation (in Gremlin console):
```groovy
g.V().count()
g.E().count()
```

## Notes
- Always run schema initialization before importing data.
- Use dynamic pod lookup (`$JG_POD`) to avoid hardcoding pod names.
- If pod container names differ, ensure you target the `janusgraph` container in `kubectl exec`.
- After building a custom JanusGraph image (with CDC JAR), update the image tag in `helmcharts/images.yaml` and redeploy.

---

## JanusGraph CDC Log Processor - Setup Guide

### Overview
The JanusGraph CDC (Change Data Capture) Log Processor is a standalone JAR that runs inside JanusGraph Server. It automatically captures graph mutations and publishes them to Kafka without requiring any application code changes.

### Prerequisites
- Maven (for building the JAR)

### Build the CDC extension JAR
Refer to the official janusgraph-cdc-extension repository for build instructions (Maven recommended):

```bash
git clone https://github.com/Sanketika-Bengaluru/knowledge-platform-db-extensions.git
cd knowledge-platform-db-extensions/janusgraph-cdc-extension
git checkout develop
mvn clean package -DskipTests
```

After build the JAR will be at `target/janusgraph-cdc-extension-1.0-SNAPSHOT.jar`.

### Docker image (place JAR in Docker build context)
Place the built JAR in the same directory as the `Dockerfile` (scripts/janusgraph/) and build the image.

Example Docker build (from `scripts/janusgraph` directory):
```bash
cp /path/to/target/janusgraph-cdc-extension-1.0-SNAPSHOT.jar .
docker build -t janusgraph-cdc-custom:1.1.0 .
```

Update the JanusGraph image tag in `helmcharts/images.yaml` after building and pushing your custom image.

---
