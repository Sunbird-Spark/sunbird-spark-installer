# Migration Notes

## Changes Made

### 1. Reuse Existing Resource Group
**File:** `create_tf_backend.sh`

Resource group creation is now skipped if it already exists. Update the resource group name directly in the script:
```bash
RESOURCE_GROUP_NAME="edsandboxda72f12a"   # <-- set your existing RG name here
```

### 2. Random Password Generation — Keycloak and PostgreSQL Removed
**File:** `random_passwords/main.tf`, `random_passwords/patch-passwords.yaml.tpl`

Random password generation for `keycloak` and `postgresql` removed. Only `grafana` and `superset` passwords are auto-generated. Set keycloak and postgresql passwords manually in `global-values.yaml`:
```yaml
default_passwords:
  keycloak_password: "your-password"
  postgresql_password: "your-password"
```

### 3. Skip Storage Account Creation
**File:** `storage/terragrunt.hcl`

Added `skip = true` — reusing existing storage account. After `output-file` runs, manually update `global-cloud-values.yaml` with your existing storage details:
```yaml
azure_storage_account_name: "<your-existing-storage-account>"
azure_storage_account_key: "<your-existing-access-key>"
azure_public_container_name: "<your-existing-public-container>"
azure_private_container_name: "<your-existing-private-container>"
azure_velero_container_name: "<your-existing-velero-container>"
```

### 4. Deploy Modules One by One
**File:** `install.sh`

`create_tf_resources` now deploys each module individually instead of `terragrunt run-all`:
```
network → aks → keys → output-file
```
`upload-files` is deployed separately after updating storage values:
```bash
./install.sh deploy_tf_module upload-files
```

### 5. Superset values.yaml Fix
**File:** `helmcharts/obsrvbb/charts/superset/values.yaml`

Removed invalid Helm template syntax from `values.yaml` (line 705). Changed:
```yaml
# Before (invalid — template syntax not allowed in values.yaml)
password: {{ .Values.global.superset.init.adminUser.password }}

# After
password: admin
```
