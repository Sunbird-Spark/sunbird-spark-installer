# Private AKS Cluster — Azure Bastion Setup Guide

Use this guide when `vpn_enabled: false`. Developer access to the private cluster is via **Azure Bastion** (browser-based SSH through Azure Portal — no VPN client needed).

> For the VPN path (`vpn_enabled: true`), see [README.md](README.md).

---

## How It Works

```
Owner (one time):
  run setup-installer-vm.sh
    → creates VNet + subnets + runner VM (no public IP)
    → VPN not installed

GitHub Actions (create_tf_resources):
    → creates AKS (private) + Azure Bastion host
    → Bastion lives in AzureBastionSubnet (separate from runner VM)

Developer access:
  Azure Portal → Bastion → SSH into runner VM → kubectl inside VNet
```

**Azure Bastion is a separate Azure-managed PaaS service** — not installed on the runner VM. It lives in `AzureBastionSubnet` and acts as a secure SSH proxy. Runner VM has no public IP.

**Same self-hosted runner pattern as the VPN path:** `setup-installer-vm.sh` registers the runner VM as a GitHub Actions self-hosted runner regardless of `vpn_enabled`. GitHub Actions workflows execute directly on this VM either way — the only difference between the two paths is how a *developer* reaches the VM afterward (VPN client vs. Bastion SSH), not how GitHub Actions reaches it.

---

## Prerequisites

- Azure **Owner role** on the subscription/resource group
- `az` CLI installed + logged in
- GitHub org admin access (for runner registration token)

---

## Step 1 — Set Flags in `global-values.yaml`

```yaml
vpn_enabled: false          # Bastion path — no VPN on VM
skip_network_module: true   # VNet pre-created by setup-installer-vm.sh
private_cluster_enabled: true

# Fill these — must match VNet/subnet names created by the script
vnet_name: "<building_block>-<environment>"           # e.g. "ed-dev"
aks_subnet_name: "<building_block>-<environment>-aks" # e.g. "ed-dev-aks"
runner_subnet_name: "<building_block>-<environment>-runner" # e.g. "ed-dev-runner"

# VPN fields not needed — leave as-is
```

---

## Step 2 — Edit and Run `setup-installer-vm.sh`

Edit variables at the top of the script:

```bash
TENANT_ID=""
SUBSCRIPTION_ID=""
BUILDING_BLOCK=""        # e.g. "ed"
ENVIRONMENT=""           # e.g. "dev"
RESOURCE_GROUP=""        # e.g. "ed-dev"
LOCATION=""              # e.g. "Central India"
GITHUB_ORG=""            # e.g. "Sunbird-Spark"
GITHUB_REPO=""           # leave empty for org-level runner
GITHUB_RUNNER_TOKEN=""   # GitHub → Settings → Actions → Runners → New runner
VPN_ENABLED="false"      # ← Bastion path
# PRITUNL fields not needed
```

Run:

```bash
bash private-repo-setup/scripts/setup-installer-vm.sh
```

**What it does:**
- Creates VNet (`<bb>-<env>`, 10.0.0.0/16)
- Creates AKS subnet (`<bb>-<env>-aks`, 10.0.0.0/20)
- Creates runner subnet (`<bb>-<env>-runner`, 10.0.16.0/28)
- Creates VM (Standard_B2s) in runner-subnet — **no public IP**
- Creates user-assigned managed identity with least-privilege custom role
- cloud-init installs: kubectl, helm, opentofu, terragrunt, az CLI, Docker (no VPN)
- Registers GitHub Actions runner → shows as **Idle** in GitHub

> Wait ~5 minutes after VM creation. Once runner shows **Idle**, proceed.

> **Note:** VM has no public IP — you cannot SSH directly yet. Azure Bastion is created in the next step.

---

## Step 3 — Configure GitHub Secret

Go to **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|--------|-------|
| `ANSIBLE_VAULT_PASSWORD` | Password used to encrypt `global-values.yaml` |

No Azure credential secrets needed — VM managed identity handles all Azure auth.

---

## Step 4 — Run Infrastructure (GitHub Actions)

Go to **Actions → Spark Platform Infra And Deploy → Run workflow**.

### Phase 1 — Backend + Infrastructure

Enable and run in order:
1. `1️⃣ Create Terraform backend` — creates storage for OpenTofu state
2. `3️⃣ Create infrastructure resources` — creates:
   - AKS (private cluster)
   - Storage, Key Vault
   - **`AzureBastionSubnet` (10.0.17.0/26)**
   - **Azure Bastion host** (`<bb>-<env>-bastion`, Basic SKU)

> Bastion creation takes ~10 minutes. Wait for workflow to complete fully.

After Phase 1: add DNS A record for your domain pointing to the load balancer IP shown in workflow output.

### Phase 2 — Deploy Helm Bundles

Enable `5️⃣ Install Helm components`, mode: `all`.

### Manual Alternative (via Bastion SSH)

Both phases above are just GitHub Actions wrappers around `install.sh` functions. Since Bastion gives you a shell directly on the runner VM, you can skip GitHub Actions entirely and run the same commands yourself:

```bash
cd sunbird-spark-installer/opentofu/azure/<env-name>

./install.sh create_tf_backend
./install.sh create_tf_resources
./install.sh install_helm_components
```

Useful for debugging or re-running a single failed step without waiting on a full workflow run. See `CLAUDE.md` for the full command reference.

---

## Step 5 — Developer Access via Azure Bastion

> Bastion is now live after `create_tf_resources` completes.

1. Go to **Azure Portal** → your resource group → `<bb>-<env>-bastion`
2. Click **Connect** → select the runner VM → **SSH**
3. Enter username: `azureuser`
4. Use the SSH private key (in `~/.ssh/` on the operator's laptop, generated by `setup-installer-vm.sh`)
5. Once inside the VM:

```bash
# Get AKS credentials (already done by cloud-init on runner, but if needed manually)
az aks get-credentials --resource-group <resource-group> --name <bb>-<env> --overwrite-existing

kubectl get pods -n sunbird
```

### Browser-Based SSH (no key needed)

Azure Bastion also supports browser-based SSH directly in the portal — no SSH client or key required:

1. Azure Portal → VM → **Connect** → **Bastion**
2. Enter `azureuser` + SSH key → **Connect**
3. Browser SSH session opens

---

## Network Layout

```
VNet: <bb>-<env>  (10.0.0.0/16)
├── <bb>-<env>-aks      (10.0.0.0/20)   ← AKS nodes
├── <bb>-<env>-runner   (10.0.16.0/28)  ← Runner VM (no public IP)
└── AzureBastionSubnet  (10.0.17.0/26)  ← Azure Bastion PaaS service
```

---

## Troubleshooting

**Runner not showing in GitHub after 5 min**

VM has no public IP — check cloud-init logs via Bastion once it's created, or check Azure VM serial console:

```
Azure Portal → VM → Boot diagnostics → Serial log
```

**`az aks get-credentials` fails — cluster not found**

Ensure `global.building_block` + `global.environment` match what was used during infra. Cluster name is `{building_block}-{environment}`.

**Bastion shows "provisioning" in Azure Portal**

Normal — Bastion takes ~10 minutes to become active after `create_tf_resources`.

**kubectl fails after Bastion SSH**

Run `az aks get-credentials` first inside the VM:
```bash
az login --identity
az aks get-credentials --resource-group <rg> --name <bb>-<env> --overwrite-existing
kubectl get pods -n sunbird
```
