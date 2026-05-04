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
| `global.aks_version` | Kubernetes version to pin on the AKS cluster (e.g. `"1.35.1"`). Leave blank to let Azure use the latest supported version. |

> Using Let's Encrypt? Set `global.lets_encrypt_ssl: true` and `global.cert_notifications.email`. Leave `proxy_private_key` and `proxy_certificate` blank.

## AKS Kubernetes Version

### Pinning the version

Set `global.aks_version` in `opentofu/azure/<env>/global-values.yaml` to lock the cluster to a specific Kubernetes release:

```yaml
global:
  aks_version: "1.35.1"   # pin AKS Kubernetes version — leave empty to use Azure's latest
```

When the field is empty or omitted, Azure provisions the cluster with its current default (latest GA) version. For production clusters, pinning is recommended so that automatic Azure maintenance does not silently change the version during a re-apply.

### Checking available versions

Before upgrading, list the versions available in your region:

```bash
az aks get-versions --location <your-region> --output table
```

Example output (truncated):

```
KubernetesVersion    Upgrades                                                                    Capabilities
-------------------  --------------------------------------------------------------------------  ---------------------------------------
1.35.3               None available                                                              KubernetesOfficial, AKSLongTermSupport
1.35.2               1.35.3                                                                      KubernetesOfficial, AKSLongTermSupport
1.35.1               1.35.2, 1.35.3                                                              KubernetesOfficial, AKSLongTermSupport
1.35.0               1.35.1, 1.35.2, 1.35.3                                                      KubernetesOfficial, AKSLongTermSupport
1.34.6               1.35.0, 1.35.1, 1.35.2, 1.35.3                                             KubernetesOfficial, AKSLongTermSupport
1.34.5               1.34.6, 1.35.0, 1.35.1, 1.35.2, 1.35.3                                     KubernetesOfficial, AKSLongTermSupport
1.34.4               1.34.5, 1.34.6, 1.35.0, 1.35.1, 1.35.2, 1.35.3                             KubernetesOfficial, AKSLongTermSupport
1.33.6               1.33.7, 1.33.8, 1.33.9, 1.33.10, 1.34.0, 1.34.1, 1.34.2, 1.34.3, 1.34.4   KubernetesOfficial, AKSLongTermSupport
```

The **Upgrades** column shows every version your current cluster can move to in a single operation. To reach a version that is not listed, you must upgrade in hops.

**Example — upgrading from `1.33.6` to `1.35.3`**

Looking at the `1.33.6` row, the highest available target is `1.34.4` — `1.35.x` does not appear. So a direct jump is not possible. The two-hop path is:

```
1.33.6  →  1.34.4  →  1.35.3
```

1. Set `aks_version: "1.34.4"` in `global-values.yaml` and apply.
2. Once the cluster is on `1.34.4`, set `aks_version: "1.35.3"` and apply again.

Always pick the **latest available patch** of the target minor version from the Upgrades list to get the most recent fixes in each hop.

### When to upgrade

| Trigger | Action |
|---------|--------|
| Azure announces end-of-support for your minor version (~12 months notice) | Plan an upgrade before the retirement date. |
| A CVE patch is released for your current minor version | Upgrade to the latest patch of the same minor (e.g. `1.34.3` → `1.34.7`). |
| A new minor version is required for a feature or dependency | Follow the incremental upgrade path below. |

### Step-by-step upgrade process

1. **Check available versions**

   ```bash
   az aks get-versions --location <your-region> --output table
   ```

   Identify the upgrade path. If you need to traverse multiple minor versions, plan each hop separately.

2. **Determine the next target version**

   Pick the version shown in the **Upgrades** column for your current version. If the final target is two or more minor versions away, start with the first intermediate version.

3. **Update `global-values.yaml`**

   Edit `opentofu/azure/<env>/global-values.yaml` (or the encrypted copy in your private repo):

   ```yaml
   global:
     aks_version: "1.34.4"   # set to next version in the upgrade path
   ```

4. **Apply the change**

   - **GitHub Actions**: commit the updated `global-values.yaml` and trigger the workflow (or push to the branch that runs it).  
   - **Manual / Azure VM**: run from the environment directory:

     ```bash
     cd opentofu/azure/<env>
     ./install.sh create_tf_resources
     ```

   OpenTofu will detect the version change, upgrade the AKS control plane, and then perform a rolling replacement of the worker nodes. This typically takes **15–30 minutes** per hop.

5. **Verify the upgrade**

   ```bash
   kubectl version --short
   # or
   az aks show --resource-group <rg-name> --name <cluster-name> --query kubernetesVersion -o tsv
   ```

6. **Repeat for each hop** (if upgrading across multiple minor versions)

   Go back to step 3 with the next version in the path until you reach the final target.

