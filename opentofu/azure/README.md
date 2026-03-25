# Azure

Follow this document if you are setting up Sunbird-Ed on Azure

#### Required tools and permisions
1. Azure CLI (https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
2. Ensure that the user or service principal running the Terraform script has the necessary prvileges as [listed here](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/application#api-permissions)

**Note:**
We will overwrite the following files. Please take a backup of your existing files in the following locations
- `~/.config/rclone/rclone.conf`
- 

### Authentication

Post installation of the CLI tool and providing necessary permissions, use the following command to login to Azure via CLI. 

```
az login --tenant <AZURE_TENANT_ID>
```

Note: Make sure you replace the AZURE_TENANT_ID with the tenant id from Azure Console. 

---

#### Azure Infra Setup

Post login, update the `opentofu/azure/<env>/global-values.yaml` with the variables as per your environment

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
```bash
cd opentofu/azure/<env>/aks

Always run the plan first and review the output before applying:
cd opentofu/azure/<env>/aks
terragrunt plan
Check the plan output. If it shows `1 to change` with your version update, it is safe to proceed:

```
# ✅ Safe — proceed with apply
~ resource "azurerm_kubernetes_cluster" "aks" {
    ~ kubernetes_version = "1.33.0" -> "1.34.0"
}
Plan: 0 to add, 1 to change, 0 to destroy.
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

