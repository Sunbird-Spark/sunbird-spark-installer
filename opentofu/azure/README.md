# Azure

Sunbird Spark deploys on Azure AKS. Infrastructure provisioning and application deployment are both handled by the installer — you do not need to create any Azure resources manually.

## Deployment Approaches

Two approaches are available, both covering infrastructure provisioning and deployment end-to-end:

**[private-repo-setup/README.md](../../private-repo-setup/README.md)**

| Approach | Description |
|----------|-------------|
| **GitHub Actions** | Automated CI/CD using OIDC federated credentials. Infra and deployments run from a private GitHub repository — no credentials stored in GitHub. |
| **Manual via Azure VM** | An Azure VM with a system-assigned managed identity runs `install.sh` directly over SSH. No CI/CD setup needed. |

## What Gets Provisioned

OpenTofu modules in `opentofu/azure/modules/` create:

| Resource | Purpose |
|----------|---------|
| AKS cluster | 2 × Standard_B16as_v2 nodes (16 vCPU / 64 GB RAM each) |
| Virtual Network | Dedicated VNet and subnet for AKS |
| Storage Account | Cloud storage for Sunbird content and backups |
| Key Vault | Secrets management |
| Managed Identity | Workload identity for AKS pods |
| OpenTofu state backend | Azure Storage container for Terraform state |

## global-values.yaml Reference

The main configuration file at `opentofu/azure/<env>/global-values.yaml` is filled in before running the installer. Key fields:

| Field | Description |
|-------|-------------|
| `global.building_block` | Short prefix for all Azure resources (e.g. `"myorg"`). Lowercase letters only. |
| `global.env` | Short environment tag used inside the cluster (e.g. `"demo"`). |
| `global.environment` | 1–9 lowercase alphanumeric. Must match the `configs/` folder name. |
| `global.domain` | Your domain (e.g. `"sunbird.myorg.com"`). |
| `global.subscription_id` | Your Azure Subscription ID. |
| `global.cloud_storage_region` | Azure region (e.g. `"eastus"`, `"centralindia"`). |
| `global.proxy_private_key` | SSL/TLS private key in PEM format. |
| `global.proxy_certificate` | SSL/TLS certificate chain in PEM format (cert + CA bundle). |

> Using Let's Encrypt? Set `global.lets_encrypt_ssl: true` and `global.cert_notifications.email`. Leave `proxy_private_key` and `proxy_certificate` blank.
