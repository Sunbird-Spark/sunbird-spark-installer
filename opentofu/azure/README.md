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

---

#### Azure Infra Setup

## global-values.yaml Reference

```
  building_block: "" # building block name
  env: "" 
  environment: "" # use lowercase alphanumeric string between 1-9 characters
  domain: ""
  subscription_id: ""
  sunbird_cloud_storage_provider: azure 
  sunbird_google_captcha_site_key: 
  google_captcha_private_key: 
  sunbird_google_oauth_clientId: 
  sunbird_google_oauth_clientSecret: 
  mail_server_from_email: ""
  mail_server_password: ""
  mail_server_host: smtp.sendgrid.net
  mail_server_port: "587"
  mail_server_username: apikey
  sunbird_msg_91_auth: ""
  sunbird_msg_sender: ""
  youtube_apikey: ""
  proxy_private_key: |
   <private_key_generated_when_setting_up_ssl>
  proxy_certificate: |
   <certificate_generated_when_setting_up_ssl>
```
## AKS Kubernetes Version Upgrade

The AKS cluster is provisioned with a default Kubernetes version defined in `opentofu/azure/modules/aks/variables.tf`. AKS versions have a support lifecycle of approximately **12 months** after GA. When a version approaches end of life, you must upgrade to a supported version.

### When to Upgrade

AKS supports the **3 latest GA minor versions** at any time. Once your version falls outside this window, Microsoft may auto-upgrade your cluster. It is recommended to upgrade proactively before that happens.

Check the currently supported AKS versions at: https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions

### How to Upgrade

**Step 1 — Update the `aks_version` default in `opentofu/azure/modules/aks/variables.tf`:**
```hcl
variable "aks_version" {
  type        = string
  description = "AKS cluster version"
  default     = "<new-version>"  # e.g. "1.34.0"
}
```

**Step 2 — Apply via OpenTofu:**
``bash
cd opentofu/azure//aks
terragrunt plan
```

Check the plan output. If it shows `1 to change` with your version update, it is safe to proceed:

```
~ resource "azurerm_kubernetes_cluster" "aks" {
    ~ kubernetes_version = "1.33.0" -> "1.34.0"
}
Plan: 0 to add, 1 to change, 0 to destroy.
```

✅ **Safe to apply** — the plan shows `1 to change` with the version update.

❌ **Do NOT apply** if the plan shows `1 to destroy` — this means the cluster will be destroyed and recreated, causing downtime. Investigate before proceeding.

**Step 3 — If the plan shows `1 to change`, apply:**

```bash
terragrunt apply
```

> **❌ Do NOT apply** if the plan shows `1 to destroy` — this means the cluster will be destroyed and recreated, causing downtime. Investigate before proceeding.

**Step 3 — If the plan shows `1 to change`, apply:**

```bash
terragrunt apply
```

> **Note:** AKS only supports upgrading **one minor version at a time** (e.g., 1.33 → 1.34 → 1.35). You cannot skip versions.

### Upgrade Behavior: No Downtime Expected

When `aks_version` is updated, OpenTofu sends an in-place update to the AKS resource — **the cluster is not destroyed or recreated**. Azure performs a rolling upgrade:

1. **Control plane upgrades first** — the API server, etcd, and other control plane components are updated with no node disruption.
2. **Node pools upgrade in a rolling fashion** — Azure adds a temporary surge node (by default 1 extra node, or 33% of the pool), cordons and drains an old node, upgrades it, then moves on to the next.
3. **Workloads are rescheduled** — pods are gracefully evicted onto available nodes before each node is upgraded, so running workloads are preserved throughout.

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
