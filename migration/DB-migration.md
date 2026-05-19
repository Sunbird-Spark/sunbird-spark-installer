# Database Migration: Sunbird ED 8.1.0 → Sunbird Spark

End-to-end runbook for migrating data from a Sunbird ED 8.1.0 cluster into a new Sunbird Spark cluster.

**Supported clouds:** Azure / GCP / AWS (Blob / GCS / S3)

> **Scope:** Same-domain migration only (DNS swap at cutover). Different-domain migrations are not validated by this guide.

---

## Prerequisites — One-time setup

Before starting, complete the **one-time setup** in [`private-repo-setup/README.md`](../private-repo-setup/README.md). Required for **both** paths — 

- **GitHub Action path** (primary): create private repo, copy workflows, encrypt config, Azure OIDC + GitHub secrets/environment.
- **VM path** (alternative — see appendix at end): install CLI tools (jq, yq, opentofu, terragrunt, kubectl, helm, postman, az/gcloud), clone repos on VM, place config at `opentofu/<cloud>/<env>/`.

Finish that setup, then return here for the migration phases.

---

## Architecture

```
SOURCE CLUSTER                  OBJECT STORAGE                TARGET CLUSTER
(Sunbird ED 8.1.0)             (Blob / GCS / S3)            (Sunbird Spark)

+-----------------+             +----------------+            +------------------+
| PostgreSQL    --|--> dump --> |                |--> load -->| YugabyteDB YSQL  |
| Cassandra     --|--> CSV  --> |   Artifacts    |--> load -->| YugabyteDB YCQL  |
| Neo4j         --|--> CSV  --> |                |--> load -->| JanusGraph       |
| Elasticsearch --|--> snap --> |                |--> load -->| Elasticsearch    |
+-----------------+             +----------------+            +------------------+

     PHASE 1 (Export)              HANDOFF                      PHASE 4 (Import)
```

---

## Migration Phases — Overview

Run phases **in order**. Do not skip ahead.

| Phase | What it does | Where it runs |
|-------|-------------|---------------|
| 1 | Export DBs from OLD cluster into object storage | OLD cluster |
| 2 | Provision NEW infra (no apps yet) | Private repo + Cloud |
| 3 | Install data-tier only on NEW cluster | NEW cluster |
| 4 | Restore data one DB at a time | NEW cluster |
| 5 | Install all remaining services | NEW cluster |
| 6 | Post-deploy reconciles | NEW cluster |
| 7 | DNS swap (cutover) | DNS provider |
| 8 | Validate | NEW cluster |

---

## Phase 1 — Export from OLD Cluster

Runs inside the **source ED 8.1.0 cluster**. Produces tarballs in object storage.

### 1.1 Configure export values

Edit `migration/database/export/values.yaml` with source DB endpoints and storage credentials:

| Cloud | Required fields |
|-------|----------------|
| Azure | `storageAccount` + `accessKey` |
| GCP   | `bucket` + `serviceAccountKey` |
| AWS   | `s3Bucket` + `accessKeyId` + `secretAccessKey` + `region` |

### 1.2 Run the export chart

```bash
cd migration/database/export

helm upgrade --install database-export . \
  -f values.yaml \
  -n migration --create-namespace \
  --timeout 60m --wait
```

### 1.3 Verify artifacts in cloud storage

| Path | Content |
|------|---------|
| `<bucket>/postgresql/*.sql.gz` | PostgreSQL dumps |
| `<bucket>/cassandra/<keyspace>.tar.gz` | Cassandra keyspaces |
| `<bucket>/neo4j/neo4j_export.tar.gz` | Neo4j export |
| `<bucket>/cluster-1/snapshots/...` | Elasticsearch snapshot |

---

## Phase 2 — Provision NEW Spark Cluster (Infra Only)

Uses the **private-repo GitHub Action** (`sunbird-spark-platform.yaml`).

> This phase reuses OLD storage — it does **not** create a new storage account. The `skip_storage_module: true` flag prevents tofu from provisioning new storage.

### 2.1 Copy config templates into private repo

```
opentofu/<cloud>/template/global-values.yaml       →  configs/<env>/global-values.yaml
opentofu/<cloud>/template/global-cloud-values.yaml →  configs/<env>/global-cloud-values.yaml
```

### 2.2 Edit `global-values.yaml`

- Set `resource_group_name` as needed
- Set `skip_storage_module: true` ← **critical**

### 2.3 Fetch OLD cluster's encryption key

```bash
kubectl --context <OLD-CLUSTER-CONTEXT> \
  get configmap learn-service -n sunbird -o yaml \
  | grep sunbird_encryption_key
```

> This key is needed so the NEW cluster can decrypt PII (email/phone) migrated into YugabyteDB.

### 2.4 Edit `global-cloud-values.yaml`

Prefill with OLD storage references and the encryption key:

```yaml
global:
  cloud_storage_access_key:          <OLD storage account name>
  public_container_name:             <OLD public container>
  private_container_name:            <OLD private container>
  velero_storage_container_private:  <OLD velero container>
  sunbird_encryption_key:            "<OLD encryption key>"

```

> **Why OLD storage refs?** The NEW cluster reads existing user uploads, content, and certs directly from OLD storage — no data copy needed.

> **Why OLD encryption key?** The `learn-service` configmap uses `{{ default .Values.global.random_string .Values.global.sunbird_encryption_key }}`. Without the OLD key, PII columns will not decrypt and logins will fail.

> **Do not touch `random_string`** — keycloak client secrets, kong consumers, player session secret, and flink all depend on it.

### 2.5 Encrypt and commit both config files

```bash
ansible-vault encrypt \
  configs/<env>/global-values.yaml \
  configs/<env>/global-cloud-values.yaml

```

### 2.6 Trigger GitHub Action — infra only

Enable these inputs:

| Input | Value |
|-------|-------|
| `create_tf_backend` | ✅ |
| `backup_configs` | ✅ |
| `create_tf_resources` | ✅ |

Wait for AKS/GKE and supporting infra to complete.

---

## Phase 3 — Install Data-Tier Only

Bring up only data services so the import chart has real DBs to target. **Do not install learnbb or knowledgebb yet** — they would repopulate schemas before import runs.

Trigger the GitHub Action **3 times** in order with `install_helm: true` and `helm_mode: selective`.

| Run | Bundle | `specific_charts` | Installs |
|-----|--------|-------------------|----------|
| 1 | edbb | `kafka yugabytedb` | Kafka + YugabyteDB |
| 2 | learnbb | `elasticsearch` | Elasticsearch |
| 3 | knowledgebb | `janusgraph` | JanusGraph |

After Run 3, all target databases exist (empty/freshly schema'd) and are ready for import.

---

## Phase 4 — Import Data (One DB at a Time)

All steps use the same chart. Enable **one block at a time** in `migration/database/import/values.yaml`, run helm, verify, then proceed to the next. Do not enable all blocks simultaneously.

```bash
cd migration/database/import
```

### 4.1 PostgreSQL → YugabyteDB YSQL

```yaml
databases:
  ysql:         { enabled: true }
  ycql:         { enabled: false }
  janusgraph:   { enabled: false }
  elasticsearch:{ enabled: false }
```

```bash
helm upgrade --install database-import . \
  -f values.yaml -n migration --create-namespace \
  --timeout 60m --wait

kubectl logs -n migration -l job-name=database-import-postgres -f
```

**Verify:** `kubectl exec -it -n sunbird yb-tserver-0 -- ysqlsh -c '\l'`
Expected: `keycloak` and `registry` databases visible.

---

### 4.2 Rotate Keycloak Credentials

The PostgreSQL restore brought in OLD keycloak admin password and client secrets. Rotate them now so the NEW keycloak service (starting in Phase 5) finds matching credentials.

```yaml
databases:
  ysql: { enabled: false }

dbFixups:
  keycloakCredentials:
    enabled: true
    adminPassword: "<keycloak_password from NEW cluster's global-values.yaml>"
    secretSuffix:  "<random_string from NEW cluster's global-cloud-values.yaml>"
```

**Value sources:**

| Field | Source |
|-------|--------|
| `adminPassword` | `keycloak_password` in NEW `global-values.yaml` |
| `secretSuffix` | `random_string` in NEW `global-cloud-values.yaml` (auto-generated by OpenTofu in Phase 2) |

```bash
helm upgrade --install database-import . \
  -f values.yaml -n migration \
  --timeout 30m --wait

kubectl logs -n migration -l job-name=database-import-keycloak -f
```

> Writes directly to YSQL (`keycloak` DB). No keycloak service needed. Safe to rerun.

---

### 4.3 Cassandra → YugabyteDB YCQL

```yaml
databases:
  ycql:
    enabled: true
    sourcePrefix: "sb_"
    targetPrefix: "<global.env from NEW cluster's global-values.yaml>_"
```

> ⚠️ `targetPrefix` must match the NEW cluster's `global.env` with a trailing underscore.
> Example: `env: "dv"` → `targetPrefix: "dv_"`

```bash
helm upgrade --install database-import . \
  -f values.yaml -n migration \
  --timeout 60m --wait
```

Logs show `==> keyspace X -> Y` per keyspace and `<== Y done: tables=N rows=M`.

---

### 4.4 Neo4j → JanusGraph

```yaml
databases:
  janusgraph: { enabled: true }
```

```bash
helm upgrade --install database-import . \
  -f values.yaml -n migration \
  --timeout 30m --wait
```

Runs `import_data.groovy` → `set_graphid.groovy` → `verify_migration.groovy` inside the JanusGraph pod.

---

### 4.5 Elasticsearch → Elasticsearch

```yaml
databases:
  elasticsearch: { enabled: true }
```

```bash
helm upgrade --install database-import . \
  -f values.yaml -n migration \
  --timeout 60m --wait
```

Restores snapshot via `repository-azure` (or GCS / S3) plugin.

---

### 4.6 Backfill `createdat` Column

Backfills the `createdat` column on the YugabyteDB user table (not populated in ED 8.1.0). No service dependency.

```yaml
dbFixups:
  createdatBackfill: { enabled: true }
```

```bash
helm upgrade --install database-import . \
  -f values.yaml -n migration \
  --timeout 15m --wait
```

---

## Phase 5 — Install All Remaining Services

Trigger the GitHub Action with:

| Input | Value |
|-------|-------|
| `install_helm` | ✅ |
| `helm_mode` | `all` |

Runs all 7 bundles (monitoring, edbb, learnbb, knowledgebb, obsrvbb, inquirybb, additional). Charts already installed in Phase 3 upgrade in place — no data loss.

---

## Phase 6 — Post-Deploy Reconciles

Run **after Phase 5** — requires running keycloak and knowlg services.

### 6.1 Keycloak Realm Reconcile

Reconciles the migrated keycloak realm with the NEW chart's `realm.json` (locales, refresh-token policy, client redirectUris, auth flows).

> Migrated user accounts and passwords are **never touched**.

```yaml
postMigration:
  keycloakRealmReconcile:
    enabled: true
    adminPassword: "<keycloak_password from NEW cluster's global-values.yaml>"
```

```bash
helm upgrade --install database-import . \
  -f values.yaml -n migration \
  --timeout 30m --wait

kubectl logs -n migration -l job-name=database-import-keycloak-realm-reconcile -f
```

### 6.2 Hierarchy Fix

Regenerates content hierarchy relations via knowlg-service.

```yaml
postMigration:
  hierarchyFix: { enabled: true }
```

```bash
helm upgrade --install database-import . \
  -f values.yaml -n migration \
  --timeout 30m --wait
```

### 6.3 User Progress Sync

Syncs user course progress across frontend and backend for data consistency. Required when migrating from older Sunbird versions where progress data may be out of sync.

```yaml
postMigration:
  userProgressSync:
    enabled: true
    adminUsername: "<admin-user>"
    adminPassword: "<admin-password>"
    dryRun: false
```

> `adminUsername` and `adminPassword` must match the admin credentials of Sunbird which is created during the initialization (e.g., `admin@yopmail.com` / `Admin@123`).

```bash
helm upgrade --install database-import . \
  -f values.yaml -n migration \
  --timeout 30m --wait

kubectl logs -n migration -l job-name=database-import-user-progress-sync -f
```

> Job automatically disables `filter_processed_enrolments` in lern-env ConfigMap before sync and re-enables it after completion.

---

## Phase 7 — DNS Swap (Cutover)

### 7.1 Get the NEW cluster's nginx IP

```bash
kubectl get svc -n sunbird ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### 7.2 Update DNS

In the DNS provider (Route53 / Cloud DNS / etc.), update the A record for the OLD domain to point to the new nginx IP. Wait 5–30 minutes for propagation.

```bash
dig +short <your-domain>   # should resolve to new IP
```

---

### Recovery — Missed `sunbird_encryption_key` in Phase 2

If `sunbird_encryption_key` was not set in `global-cloud-values.yaml` during Phase 2, `learn-service` falls back to `random_string` as the encryption key. This causes login failures and garbled PII columns.

**Fix:**

1. Fetch OLD key:
```bash
kubectl --context <OLD-CLUSTER-CONTEXT> \
  get configmap learn-service -n sunbird -o yaml \
  | grep sunbird_encryption_key
```

2. Add to NEW cluster's `global-cloud-values.yaml`:
```yaml
global:
  sunbird_encryption_key: "<value from OLD cluster>"
  # Do NOT touch random_string
```

3. Re-encrypt, commit, and redeploy learn-service:
   - `helm_mode: selective`, bundle: learnbb, `specific_charts: learn-service`

---

## Phase 8 — Validate

Trigger the GitHub Action with only these inputs:

| Input | Purpose |
|-------|---------|
| `generate_postman_env` | Builds `env.json` with NEW cluster endpoints |
| `migrate_forms` | Seeds System Settings + creates/updates Forms |

**Form migration behaviour (`migrate_forms.py`):**

| API response | Action |
|-------------|--------|
| `404` | Create form |
| `200` | Update form |
| Skipped | 6 Spark Portal Creation forms (left untouched if present) |

> `run_post_install` is not needed for migrations — it is for fresh installs only.

**Manual sanity checks:**

- Login with a migrated user → password works (encryption key correct, keycloak reconciled)
- Old user-uploaded content is visible (storage refs correct)
- API endpoints return data
- Mobile app authenticates (android client redirectUris reconciled in Phase 6.1)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Login fails / PII columns garbled | `sunbird_encryption_key` not set in `global-cloud-values.yaml` | See Phase 7 recovery section |
| Old uploads return 404 | Wrong storage container names in `global-cloud-values.yaml` | Re-verify Phase 2.4 |
| Keycloak admin login fails | `keycloakCredentials` not run or wrong `adminPassword` | Rerun Phase 4.2 |
| Client secret invalid | Wrong `secretSuffix` in Phase 4.2 | Re-read `random_string` from config, rerun Phase 4.2 |
| Refresh token rejected | Realm reconcile did not apply | Rerun Phase 6.1 |
| YCQL keyspace not found | `targetPrefix` mismatch vs `global.env` | Fix prefix in Phase 4.3, rerun |
| Mobile app cannot login | android client redirectUris not updated | Check Phase 6.1 job logs |
| `helm timeout` on import job | Job is working but slow | Increase `--timeout 120m` |

---

## File Reference

| Path | Purpose |
|------|---------|
| `database/export/` | Phase 1 helm chart |
| `database/import/` | Phase 4 + 6 helm chart |
| `database/import/files/keycloak_apply_realm_reconcile.py` | Phase 6.1 realm reconciler |
| `database/import/files/user-progress-sync.py` | Phase 6.3 user progress sync |
| `database/import/keycloak_realm_diff.txt` | OLD vs NEW realm diff reference |
| `migrate_forms.py` | Phase 8 — seed System Settings and Forms |
| `export.sh` | Phase 1 orchestration on OLD cluster — 4 helm upgrades (postgresql → cassandra → neo4j → elasticsearch) |
| `migrate.sh` | Phase 4 orchestration on NEW cluster — 6 helm upgrades (YSQL → keycloakCredentials → YCQL → JanusGraph → ES → createdatBackfill) |
| `post-migrate.sh` | Phase 6 orchestration on NEW cluster — 3 helm upgrades (keycloakRealmReconcile → hierarchyFix → userProgressSync) with service-readiness preflight |

---

## Appendix — Running Without GitHub Action (VM path)

GitHub Action is the primary path. For the VM path, complete the one-time VM setup in [`private-repo-setup/README.md`](../private-repo-setup/README.md) first (CLI tools, repo clone, config placement). With the public repo cloned and config files at `opentofu/<cloud>/<env>/`, the Action inputs map to these `install.sh` calls:

| Phase | GitHub Action inputs | VM equivalent |
|-------|---------------------|---------------|
| 2 | `create_tf_backend`, `backup_configs`, `create_tf_resources` | `./install.sh create_tf_backend backup_configs create_tf_resources` |
| 3 — Run 1 | edbb, `specific_charts: kafka yugabytedb` | `./install.sh install_service edbb kafka yugabytedb` |
| 3 — Run 2 | learnbb, `specific_charts: elasticsearch` | `./install.sh install_service learnbb elasticsearch` |
| 3 — Run 3 | knowledgebb, `specific_charts: janusgraph` | `./install.sh install_service knowledgebb janusgraph` |
| 5 | `helm_mode: all` | `./install.sh install_helm_components` |
| 7 (recovery) | learnbb, `specific_charts: learn-service` | `./install.sh install_service learnbb learn-service` |
| 8 | `generate_postman_env`, `migrate_forms` | `./install.sh generate_postman_env migrate_forms` |

> Phases 1, 4, and 6 are pure `helm upgrade --install` commands and run identically in both paths.

---

### Orchestration helpers — `export.sh` + `migrate.sh` + `post-migrate.sh`

Three small scripts that wrap only the **helm-driven migration steps** (Phase 1 + Phase 4 + Phase 6). Everything else (infra, data-tier install, full deploy, validation) goes through the GitHub Action.

| Script | kubectl context | What it runs | Pre-req |
|--------|-----------------|--------------|---------|
| `migration/export.sh`       | OLD cluster | Phase 1 (4 helm upgrades: postgresql → cassandra → neo4j → elasticsearch) | export/values.yaml filled with source DB endpoints + bucket creds |
| `migration/migrate.sh`      | NEW cluster | Phase 4 (6 helm upgrades: YSQL → keycloakCredentials → YCQL → JanusGraph → ES → createdatBackfill) | Phases 1, 2, 3 done |
| `migration/post-migrate.sh` | NEW cluster | Phase 6 (3 helm upgrades: keycloakRealmReconcile → hierarchyFix → userProgressSync). **Pre-flight**: fails fast if `keycloak`/`knowlg-service`/`lern-service` in `sunbird` ns have no Ready replicas. | Phase 5 done |

No `ENV` env var required — all scripts are pure `helm` and `kubectl`; no `install.sh` calls. Just point `kubectl` at the right cluster (OLD for export, NEW for the rest).

All use `set -euo pipefail` — any non-zero exit halts execution; subsequent steps do **not** run. Fix root cause, rerun the failed step.

#### End-to-end flow

```bash
# ----- on OLD cluster (kubectl context = OLD) -----
# 1. Phase 1 — export 4 source DBs to object storage
./migration/export.sh

# ----- switch kubectl context to NEW cluster -----

# 2. Phase 2 — trigger GitHub Action: create_tf_backend + backup_configs + create_tf_resources
# 3. Phase 3 — trigger GitHub Action: install_helm=true, helm_mode=selective
#    Run Action 3 times:
#      Run 1: bundle=edbb,         specific_charts="kafka yugabytedb"
#      Run 2: bundle=learnbb,      specific_charts="elasticsearch"
#      Run 3: bundle=knowledgebb,  specific_charts="janusgraph"

# 4. Phase 4 — DB imports + DB-only fixups
./migration/migrate.sh

# 5. Phase 5 — trigger GitHub Action: install_helm=true, helm_mode=all
#    Wait until Deployments in ns/sunbird are Ready.

# 6. Phase 6 — post-deploy reconciles (preflight checks services first)
./migration/post-migrate.sh

# 7. Phase 8 — trigger GitHub Action: generate_postman_env + migrate_forms

# 8. Phase 7 — DNS swap (manual)
```

#### Per-step invocations (recommended for first-time runs — verify each before moving on)

```bash
# OLD cluster
./migration/export.sh 1.1
./migration/export.sh 1.2
./migration/export.sh 1.3
./migration/export.sh 1.4

# NEW cluster (after Phases 2 + 3 via Action)
./migration/migrate.sh 4.1
./migration/migrate.sh 4.2
./migration/migrate.sh 4.3
./migration/migrate.sh 4.4
./migration/migrate.sh 4.5
./migration/migrate.sh 4.6

# After Phase 5 via Action
./migration/post-migrate.sh 6.1
./migration/post-migrate.sh 6.2
./migration/post-migrate.sh 6.3
```

> **How does `post-migrate.sh` know Phase 5 is done?** It doesn't trust a flag — it queries `kubectl` for `keycloak` / `knowlg-service` / `lern-service` Deployments in `sunbird` ns and requires each has ≥ 1 Ready replica. If any check fails the script exits with a clear error. Wait for the Action to finish + pods to become Ready, then rerun.

Inputs (env vars):

| Var | Default | Purpose |
|-----|---------|---------|
| `ENV` | — (required) | Env name under `opentofu/<cloud>/<env>/` |
| `CLOUD` | `azure` | `azure` or `gcp` |
| `NAMESPACE` | `migration` | Helm release namespace for the import chart |
| `RELEASE` | `db-migration` | Helm release name |
| `HELM_TIMEOUT` | `60m` | Per-helm-upgrade timeout |