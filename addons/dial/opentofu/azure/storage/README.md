# DIAL Storage Container - OpenTofu Module

This module creates the DIAL storage container separately from the main infrastructure.

## Prerequisites

1. Main infrastructure must be deployed first (storage account must exist)
2. Backend environment variables must be set (same as main opentofu)
3. `global-values.yaml` and `global-cloud-values.yaml` must exist in main opentofu directory

## Usage

### Prerequisites

1. Main infrastructure must be deployed first
2. Set environment variables by sourcing tf.sh:
   ```bash
   cd <repo-root>/opentofu/azure/<your-env>
   source tf.sh
   ```

### Create DIAL Container

```bash
cd addons/dial/opentofu/azure/storage
terragrunt init
terragrunt plan
terragrunt apply
```

### Destroy DIAL Container

```bash
cd addons/dial/opentofu/azure/storage
terragrunt destroy
```

## Backend Configuration

This module uses the **same backend state container** as the main infrastructure but with a different state key:

- **Main infra state key**: `storage/tofu.tfstate`
- **DIAL addon state key**: `addons/dial/storage/tofu.tfstate`

This ensures complete isolation - creating/destroying DIAL container won't affect main infrastructure.

## Outputs

- `dial_state_container_name`: Name of the created DIAL container
- `storage_account_name`: Storage account name (for reference)

## Notes

- The container name format: `{environment}-dial-{unique_uuid}`
- Container access type: `blob` (public read access)
- References existing storage account via data source (doesn't create new one)
