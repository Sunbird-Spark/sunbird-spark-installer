# GCP Setup — Sunbird Spark Installer

Codename: **`gcp-no-keys`**

End-to-end GCP setup: zero JSON service-account keys, GitHub Actions auth via Workload Identity Federation, independent module deployment.

---

## Step 1 — GitHub Actions auth (DONE — scripts written)

Two bootstrap scripts under `private-repo-setup/scripts/`. User runs once with project Owner.

| Script | Purpose |
|---|---|
| `gcp-setup-infra-sa.sh` | Creates WI Pool + GitHub OIDC provider + infra SA + custom `installer_role` (project scope) + WIF impersonation binding. **Used by Phase 1 workflow** (provisioning). |
| `gcp-setup-deploy-sa.sh` | Creates deploy SA + cluster-scoped roles + bucket read + WIF binding. Reuses pool. **Used by Phase 2 workflow** (helm/kubectl). Run after cluster exists. |

### How it works

```
GitHub Actions runner
  │
  ├─> requests OIDC token from GitHub (signed JWT, short-lived)
  │
  ├─> google-github-actions/auth@v2 sends token to GCP STS
  │     (provider path: GCP_WORKLOAD_IDENTITY_PROVIDER)
  │
  ├─> GCP STS validates:
  │     - issuer == https://token.actions.githubusercontent.com
  │     - assertion.repository == <pinned repo via attribute-condition>
  │     - principalSet matches: attribute.repository/<GITHUB_REPO>
  │
  ├─> STS returns federated access token
  │
  ├─> Token impersonates target SA:
  │     Phase 1 -> GCP_INFRA_SA_EMAIL  (installer_role at project scope)
  │     Phase 2 -> GCP_DEPLOY_SA_EMAIL (cluster-scoped + bucket read)
  │
  └─> Tofu / gcloud / helm / kubectl uses ADC from impersonation
```

No JSON keys at any layer. Tokens short-lived (1 hour). Pinned to repo via `attribute-condition`.

### Roles granted

**Infra SA — custom `installer_role` (project scope):**
- `compute.networks/subnetworks/routers/firewalls.*` — for `network/` module
- `container.clusters/operations/nodes.*` — for `gke/` module
- `storage.buckets.*` + `storage.objects.*` — for `storage/` module + state backend
- `iam.serviceAccounts.*` + `iam.roles.*` + project IAM — for `workload-identity/` module
- `serviceusage.services.*` — API enablement

**NOT granted to infra SA (hard guarantee no keys):**
- `iam.serviceAccountKeys.create`
- `iam.serviceAccountKeys.delete`
- `iam.serviceAccountKeys.get`
- `iam.serviceAccountKeys.list`

**Deploy SA — predefined roles, scoped:**

| Role | Scope |
|---|---|
| `roles/container.clusterViewer` | single cluster (IAM condition) |
| `roles/container.developer` | single cluster (IAM condition) |
| `roles/storage.objectViewer` | private bucket only |

**NOT granted to deploy SA:** any `*.admin`, `objectAdmin`, IAM-mutating role.

### GitHub Actions secrets

| Secret | Source |
|---|---|
| `GCP_PROJECT_ID` | manual |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `gcp-setup-infra-sa.sh` output |
| `GCP_INFRA_SA_EMAIL` | `gcp-setup-infra-sa.sh` output |
| `GCP_DEPLOY_SA_EMAIL` | `gcp-setup-deploy-sa.sh` output |
| `ANSIBLE_VAULT_PASSWORD` | manual |

### Workflow auth pattern

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account:            ${{ secrets.GCP_INFRA_SA_EMAIL }}    # Phase 1
    # service_account:          ${{ secrets.GCP_DEPLOY_SA_EMAIL }}   # Phase 2
```

### Verification

```bash
# Confirm no key perms in installer_role
gcloud iam roles describe ${BUILDING_BLOCK}_${ENVIRONMENT}_installer_role \
  --project=$PROJECT_ID --format="value(includedPermissions)" \
  | grep -i 'serviceAccountKeys' && echo FAIL || echo PASS

# Confirm deploy SA has no admin/owner/editor
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:$DEPLOY_SA_EMAIL" \
  --format="value(bindings.role)" \
  | grep -E 'admin|owner|editor' && echo FAIL || echo PASS
```
Both must print `PASS`.

---

## Step 2 — Tofu module changes (NEXT)

Goal: remove all key generation from Tofu. Modules independently deployable. Strip key references from rclone + output template + downstream consumers.

### 2.1 Storage reuse flag (`skip_storage_module`)

Add to `template/global-values.yaml`:
```yaml
global:
  skip_storage_module: false  # true = use existing global-cloud-values.yaml
```

| Flag value | Behavior |
|---|---|
| `false` | `storage` module runs. Creates buckets. Downstream modules consume `dependency.storage.outputs`. |
| `true` | `storage` module skipped. Downstream modules read bucket names from existing `global-cloud-values.yaml` via `try(yamldecode(...))`. |

Permanent dual-mode (not migration). Wired in `_common/*.hcl` via `skip_outputs = local.skip_storage_module` + ternary picks.

### 2.2 Remove keys from `service-account/` module → rename `workload-identity/`

**Drop:**
- `google_service_account_key.service_account`
- `local_file.service_account` (writes `sa-keys/*.json`)
- `google_storage_bucket_object.gke_service_account` (uploads key to GCS)
- `google_project_iam_member.storage_admin_role` (project-wide storage admin)

**Drop outputs:**
- `service_account_key_local_path`
- `service_account_private_key`
- `cloud_storage_private_key_id`

**Drop variables:**
- `google_service_account_key_path`
- `sa_key_store_bucket`

**Add:**
- `google_project_iam_custom_role` — object-level perms only (`storage.objects.{get,list,create,delete,update}`, `storage.buckets.get`)
- `google_storage_bucket_iam_member` — per bucket, binds GCP SA to custom role at bucket scope
- `kubernetes_namespace` — `sunbird`, `velero`
- `kubernetes_service_account` — annotated with `iam.gke.io/gcp-service-account = <gcp-sa-email>`

### 2.3 Output template — strip key fields

`modules/output-file/global-cloud-values.yaml.tfpl`:

**Drop:**
- `cloud_storage_secret_key: ${gcp_storage_account_key}` <- secret leak
- `cloud_storage_private_key_id: ${cloud_storage_private_key_id}`

**Add:**
- `cloud_storage_auth_type: WORKLOAD_IDENTITY`
- `service_account_email: ${service_account_email}`
- `workload_identity_service_account_name: ${k8s_service_account_name}`

`gsutil cp` -> `gcloud storage cp` (uses ADC).

### 2.4 `upload-files/` module — rclone uses ADC

`modules/upload-files/config.tfpl`:

```
[ownaccount]
type = google cloud storage
project_number = ${project_number}
env_auth = true
# Uses ADC from `gcloud auth application-default login` or attached SA.
```

**Drop variable:** `storage_account_primary_access_key`
**Add variable:** `project_number`

### 2.5 Public bucket grant downgrade

`modules/storage/main.tf`:
- `google_storage_bucket_iam_member.read_write_public` — `roles/storage.objectAdmin@allUsers` -> `roles/storage.objectViewer@allUsers`
- `google_storage_bucket_iam_member.full_access_dial` — same downgrade

Public read kept (app needs anonymous fetch). Public write removed.

### 2.6 `gke/` module — expose K8s provider auth outputs

Add outputs:
- `kubernetes_host` (`google_container_cluster.cluster.endpoint`)
- `cluster_ca_certificate` (`master_auth[0].cluster_ca_certificate`)

Used by renamed `workload-identity/` module's kubernetes provider via `data.google_client_config.default.access_token`.

### 2.7 Hunt + remove key references everywhere

Sweep for `cloud_storage_secret_key` / `gcp_storage_account_key` / `service_account_private_key` / `cloud_storage_private_key_id`:

```bash
grep -rn 'cloud_storage_secret_key\|service_account_private_key\|cloud_storage_private_key_id\|gcp_storage_account_key' \
  /Users/divya/Documents/cossallenv/gcp/sunbird-spark-installer
```

Helm chart consumers flagged as separate sweep (follow-up ticket).

---

## Out of scope
- Helm chart code consuming `cloud_storage_secret_key` — separate sweep.
- Public bucket existence — kept.
- GKE control-plane endpoint — already supports private mode.

## Recommended (manual)
- Org policy: `constraints/iam.disableServiceAccountKeyCreation = enforced` at org/folder level.
