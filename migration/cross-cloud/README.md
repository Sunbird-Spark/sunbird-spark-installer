# Cross-Cloud Migration: Sunbird ED 8.1.0 → Sunbird Spark

End-to-end runbook for migrating an existing Sunbird ED cluster to a new Sunbird Spark cluster (any cloud).

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

## High-level flow

| # | Phase | Where | Action |
|---|---|---|---|
| 1 | **Export** | OLD cluster (ED 8.1.0) | Run `database-export` chart → push artifacts to bucket |
| 2 | **Provision** | New env | Create Spark cluster via private repo GitHub Action |
| 3 | **Bootstrap services** | NEW cluster | Install kafka, yugabyte, elasticsearch, learn, knowledge, janusgraph (only) |
| 4 | **Import** | NEW cluster | Run `database-import` chart per database (postgres → keycloak → cassandra → neo4j → es) |
| 5 | **Full deploy** | NEW cluster | Install all remaining bundles via `install.sh` |
| 6 | **Manual config** | NEW cluster | Patch `sunbird_encryption_key`, swap DNS to point old domain at new nginx |
| 7 | **Validate** | NEW cluster | Postman env.json + `setup_forms.py` |

---

## Phase 1 — Export from OLD cluster

Runs **inside source ED 8.1.0 cluster**. Produces tarballs in object storage.

```bash
cd migration/cross-cloud/database-export

# Edit values.yaml: set source DB endpoints, bucket creds, storage paths
# (azure: storageAccount + accessKey, gcp: bucket + serviceAccountKey, aws: s3Bucket + keys)

helm upgrade --install database-export . \
  -f values.yaml \
  -n migration --create-namespace \
  --timeout 60m --wait
```

Verify in cloud console:
- `<bucket>/postgresql/*.sql.gz`
- `<bucket>/cassandra/<keyspace>.tar.gz`
- `<bucket>/neo4j/neo4j_export.tar.gz`
- `<bucket>/cluster-1/snapshots/...` (ES snapshot)

---

## Phase 2 — Create NEW Spark cluster

Use the **private infra repo's GitHub Action** to provision the cluster.

1. Copy from public repo into private repo:
   - `opentofu/<cloud>/template/global-values.yaml`
   - `opentofu/<cloud>/template/global-cloud-values.yaml`

2. Edit `global-values.yaml` in private repo:
   - Set `resource_group_name` to a NEW name (don't reuse old cluster's RG)
   - Set `skip_storage_module: true` ← critical: prevents creating new storage account; reuses OLD cluster's storage

3. Edit `global-cloud-values.yaml`:
   - `storage_account_name` → **OLD cluster's** storage account
   - `cloud_storage_resource_group_name` → **OLD cluster's** RG (only for Azure)
   - Public/private container names → **OLD cluster's** containers
   - This lets the new cluster read existing user uploads, content, certs from OLD storage

4. Trigger GitHub Action per the private repo's README. Wait for AKS/GKE + supporting infra to come up.

---

## Phase 3 — Bootstrap critical services only

Don't deploy everything yet. Only the data-tier first so import can target real DBs.

```bash
cd opentofu/<cloud>/<env>     # the env directory created from template

# Bring up monitoring + edbb foundations (kafka comes via edbb)
./install.sh install_service edbb kafka

# Bring up data tier
./install.sh install_service learnbb yugabytedb
./install.sh install_service learnbb elasticsearch

# Bring up learn-side services that own their schemas (creates DBs/keyspaces)
./install.sh install_component learnbb           # learn + keycloak (skips data refill)
./install.sh install_service knowledgebb janusgraph
./install.sh install_component knowledgebb       # knowledge platform jobs etc.
```

After this step, target DBs exist (empty/freshly-schema'd) and import can land on them.

---

## Phase 4 — Run database-import (one DB at a time)

Inside `migration/cross-cloud/database-import/values.yaml`, **enable one block at a time**, run helm, verify, move to next. Don't enable all at once.

### 4.1 PostgreSQL → YugabyteDB YSQL

```yaml
databases:
  yugabytedb:
    enabled: true        # <-- only this
  ycql:
    enabled: false
  janusgraph:
    enabled: false
  elasticsearch:
    enabled: false
```

```bash
cd migration/cross-cloud/database-import
helm upgrade --install database-import . -f values.yaml -n migration --create-namespace --timeout 60m --wait
kubectl logs -n migration -l job-name=database-import-postgres -f
```

Verify: `kubectl exec -it -n sunbird yb-tserver-0 -- ysqlsh -c '\l'` → see `keycloak`, `registry`.

### 4.2 Keycloak realm-diff (post-postgres)

Postgres restore brings in the OLD realm. Apply chart's realm config diffs without wiping users:

```yaml
postMigration:
  keycloakRealmDiff:
    enabled: true
    adminPassword: "<KC admin pwd from old cluster>"
```

```bash
helm upgrade --install database-import . -f values.yaml -n migration --create-namespace --timeout 30m --wait
kubectl logs -n migration -l job-name=database-import-keycloak-realm-diff -f
```

This script:
- PUTs realm-level settings (locales, refresh token policy)
- Updates client config (redirectUris, attributes for android/google-auth/portal)
- Creates new auth flows (`Direct Grant with Password`)
- **Never touches `/users`** — migrated user accounts + passwords stay intact

### 4.3 Cassandra → YugabyteDB YCQL

```yaml
databases:
  ycql:
    enabled: true
```

```bash
helm upgrade --install database-import . -f values.yaml -n migration --timeout 60m --wait
```

Logs show `==> keyspace X -> Y` per keyspace, `<== Y done: tables=N rows=M`.

### 4.4 Neo4j → JanusGraph

```yaml
databases:
  janusgraph:
    enabled: true
```

```bash
helm upgrade --install database-import . -f values.yaml -n migration --timeout 30m --wait
```

Job runs `import_data.groovy` → `set_graphid.groovy` → `verify_migration.groovy` inside janusgraph pod.

### 4.5 Elasticsearch → Elasticsearch

```yaml
databases:
  elasticsearch:
    enabled: true
```

```bash
helm upgrade --install database-import . -f values.yaml -n migration --timeout 60m --wait
```

Restores snapshot via repository-azure (or GCS/S3) plugin.

### 4.6 Optional post-migration fixups

- `postMigration.createdatBackfill` — backfill `createdat` column on YB user table
- `postMigration.hierarchyFix` — regenerate hierarchy relations for migrated content
- `postMigration.keycloakCredentials` — rotate keycloak admin password / client secrets

Enable per-need, rerun helm.

---

## Phase 5 — Deploy all remaining services

```bash
cd opentofu/<cloud>/<env>
./install.sh install_helm_components
```

This runs all 7 building blocks (monitoring, edbb, learnbb, knowledgebb, obsrvbb, inquirybb, additional). Already-installed services upgrade in place.

---

## Phase 6 — Manual config (cannot be automated)

### 6.1 sunbird_encryption_key

Pull from OLD cluster:

```bash
kubectl --context <OLD-CLUSTER-CONTEXT> get configmap learn-service -n sunbird -o yaml \
  | grep sunbird_encryption_key
```

Set in NEW cluster's `global-values.yaml`:

```yaml
sunbird_encryption_key: "<value from old cluster>"
```

Then redeploy learn-service:

```bash
./install.sh install_service learnbb learn-service
```

**Why:** PII fields (email/phone) in YB are encrypted with this key. New cluster needs same key to decrypt migrated data.

### 6.2 DNS swap to new nginx

Get new cluster's nginx external IP:

```bash
kubectl get svc -n sunbird ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

In your DNS provider (Route53 / Cloud DNS / etc.), update the A record for the OLD cluster's domain (e.g. `sandbox.sunbirded.org`) to point at the new nginx IP.

Wait for propagation (5–30 min). Verify:

```bash
dig +short sandbox.sunbirded.org
# Should show new cluster's IP
```

---

## Phase 7 — Validate

```bash
cd opentofu/<cloud>/<env>
./install.sh generate_postman_env       # builds env.json with new cluster endpoints
./install.sh run_post_install           # runs Postman collection

# Forms setup
python3 setup_forms.py                  # whatever script your env uses
```

Check:
- Login with a migrated user → password works
- Old user-uploaded content visible (storage handoff working)
- API endpoints return data
- Mobile app can authenticate

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Login fails after import | `sunbird_encryption_key` mismatch | Phase 6.1 |
| Old uploads 404 | Storage container name wrong in `global-cloud-values.yaml` | Reconfirm Phase 2.3 |
| Keycloak "user not found" | Postgres restore didn't run | Rerun 4.1 |
| Refresh token rejected | Realm diff didn't apply | Rerun 4.2 |
| Mobile app can't login | android client redirectUris not updated | Check `keycloakRealmDiff` job logs |
| `helm timeout` on import | Job working but slow | Increase `--timeout 60m` |

---

## File reference

| Path | Purpose |
|---|---|
| `database-export/` | Phase 1 helm chart |
| `database-import/` | Phase 2 helm chart |
| `database-import/files/keycloak_apply_realm_diff.py` | Realm config patcher (preserves users) |
| `database-import/keycloak_realm_diff.txt` | Old vs new realm diff reference |

---

## Idempotency

All import steps safe to rerun:

| Step | Mechanism |
|---|---|
| Postgres | DROP DATABASE → CREATE → restore |
| Cassandra | TRUNCATE → INSERT (per table, `truncateBeforeLoad: true`) |
| ES | DELETE indices → restore snapshot |
| JanusGraph | skip-if-vertex-exists (no dupes) |
| Realm diff | DELETE old protocolMappers → POST new (no dupes) |
| createdat backfill | UPDATE with WHERE — deterministic |
