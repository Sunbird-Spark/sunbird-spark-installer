# Sunbird Spark — Private Deployment Repository Setup

This guide walks through creating a **private GitHub repository** that holds your environment configuration (encrypted) and GitHub Actions workflows to deploy Sunbird Spark using `sunbird-spark-installer` as the source.

> Throughout this guide, `demo` is used as the environment name. Replace it with your own (e.g. `production`, `staging`, `uat`).

---

## Choose Your Deployment Path

| Path | When to use |
|------|-------------|
| **Self-hosted runner + Managed Identity** *(recommended)* | Private AKS cluster, no Azure credentials stored anywhere, VPN access for developers |
| **GitHub Actions (OIDC)** | Public AKS cluster, Azure OIDC auth via service principals |
| **Manual via Azure VM** | Quick start — SSH into a VM and run `install.sh` directly |

This guide covers the **Self-hosted runner** path. For the OIDC path, see [OIDC Setup](#github-actions-oidc-path).

---

## Self-Hosted Runner Path (Recommended)

### How it works

```
Owner (one time):
  run setup-installer-vm.sh
    → creates VM + managed identity + Pritunl VPN + GitHub runner

GitHub Actions (all future deployments):
  runs on self-hosted runner (VM inside VNet)
    → VM managed identity handles Azure auth (no credentials needed)
    → can reach private AKS cluster
```

**Benefits:**
- AKS API server is private — not accessible from internet
- No Azure credentials stored in GitHub secrets
- Developers connect via Pritunl VPN to access cluster
- One VM = VPN server + CI/CD runner

---

## Repository Structure

```
spark-devops/
├── .github/
│   └── workflows/
│       ├── sunbird-spark-platform.yaml     ← main deployment workflow
│       └── sunbird-spark-addons.yaml       ← addons workflow (optional)
└── configs/
    └── demo/                               ← your environment name
        ├── global-values.yaml              ← YOU create this (encrypted)
        ├── global-cloud-values.yaml        ← auto-generated after infra run
        ├── tf.sh                           ← auto-generated after backend creation
        └── env.json                        ← auto-generated after post-install
```

> **Do not manually create** `global-cloud-values.yaml`, `tf.sh`, or `env.json` — the workflows generate and commit them automatically.

---

## Step 1 — Create the Private Repository

1. Create a new **private** repository in your GitHub account or organization.

2. Clone it locally and create the folder structure:

```bash
git clone https://github.com/org-name/spark-devops.git
cd spark-devops
mkdir -p .github/workflows configs/demo
```

---

## Step 2 — Copy Workflow Templates

```bash
INSTALLER_PATH=/path/to/sunbird-spark-installer

cp $INSTALLER_PATH/private-repo-setup/.github/workflows/sunbird-spark-platform.yaml .github/workflows/
cp $INSTALLER_PATH/private-repo-setup/.github/workflows/sunbird-spark-addons.yaml .github/workflows/
```

---

## Step 3 — Prepare `global-values.yaml`

```bash
cp $INSTALLER_PATH/opentofu/azure/template/global-values.yaml configs/demo/global-values.yaml
```

Open the file and fill in all required fields — see the root [README.md](../README.md) for the full field reference.

Also fill in the VM + VPN fields added at the bottom:
```yaml
vm_size: "Standard_B2s"
vm_admin_username: "azureuser"
github_runner_token: "REPLACE_WITH_GITHUB_RUNNER_TOKEN"  # GitHub → Settings → Actions → Runners → New runner
github_org: "REPLACE_WITH_GITHUB_ORG"
pritunl_vpn_network: "172.16.0.0/24"
pritunl_org_name: "sunbird-spark"
pritunl_users:
  - name: "your-name"
    email: "your@email.com"
```

> **Important:** `global.environment` must exactly match the `configs/` folder name and the GitHub Actions environment name set in Step 6.

---

## Step 4 — Encrypt and Commit the Config

```bash
pip install ansible

ansible-vault encrypt configs/demo/global-values.yaml
# Enter a strong password and save it securely — this becomes ANSIBLE_VAULT_PASSWORD in Step 6.

git add configs/demo/global-values.yaml
git commit -m "Add encrypted environment config"
git push
```

> Confirm encryption: the file should start with `$ANSIBLE_VAULT;1.1;AES256`. Never commit it unencrypted.

---

## Step 5 — Create the Runner VM (One Time)

This script creates the VM with managed identity, installs Pritunl VPN + WireGuard + GitHub Actions runner automatically via cloud-init.

**Requires:** `az` CLI installed + Azure **Owner role** on the subscription/resource group.

Edit the variables at the top of the script:

```bash
TENANT_ID=""              # Azure Portal → Azure Active Directory → Overview
SUBSCRIPTION_ID=""        # Azure Portal → Subscriptions
BUILDING_BLOCK=""         # Must match global.building_block in global-values.yaml
ENVIRONMENT=""            # Must match your configs/ folder name (e.g. "demo")
RESOURCE_GROUP=""         # Azure resource group (e.g. "myorg-demo")
LOCATION=""               # Azure region (e.g. "Central India")
GITHUB_ORG=""             # GitHub org name (e.g. "Sunbird-Spark")
GITHUB_REPO=""            # Leave empty for org-level runner
GITHUB_RUNNER_TOKEN=""    # GitHub → Settings → Actions → Runners → New runner → copy token
PRITUNL_VPN_NETWORK=""    # VPN client IP pool (e.g. "172.16.0.0/24")
PRITUNL_ORG_NAME=""       # Pritunl org name
PRITUNL_USERS=("name:email@example.com")  # VPN users
```

Then run:

```bash
bash $INSTALLER_PATH/private-repo-setup/scripts/setup-installer-vm.sh
```

**What it creates:**
- Ubuntu 22.04 VM (`Standard_B2s`) with public IP
- User-assigned managed identity with least-privilege custom role
- AKS Cluster Admin role on resource group
- NSG rules: UDP 1194 (VPN) + TCP 443 (Pritunl UI)

**cloud-init runs automatically on VM boot (~5 min):**
- Installs: Pritunl, WireGuard, kubectl, helm, opentofu, terragrunt, az CLI, jq, yq, rclone, Docker
- Configures Pritunl VPN server + creates users
- Registers GitHub Actions runner → shows as **Idle** in GitHub

> **Wait ~5 minutes** after VM creation. Once runner shows **Idle** in GitHub → Settings → Actions → Runners, the VM is ready.

**Owner's job is done. All subsequent steps run via GitHub Actions.**

---

## Step 6 — Configure GitHub Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret | Source | Required |
|--------|--------|----------|
| `ANSIBLE_VAULT_PASSWORD` | Password from Step 4 | Always |

> With self-hosted runner + managed identity, **no Azure credentials are needed in GitHub secrets.** The VM managed identity handles all Azure auth automatically.

---

## Step 7 — Set Environment Name in Workflows

In both workflow files, replace `your-env` with your environment name:

```yaml
options:
  - demo     # your environment name
default: demo
```

```bash
git add .github/
git commit -m "Configure workflow environment name"
git push
```

---

## Step 8 — Developer VPN Access

Developers connect to the Pritunl VPN to access the private AKS cluster.

1. Open `https://<vm-public-ip>` (printed by setup script)
2. Log in with Pritunl credentials (admin set password after setup)
3. Download WireGuard profile
4. Install [WireGuard client](https://www.wireguard.com/install/) (Windows / Mac / Linux)
5. Import profile → Connect VPN
6. `kubectl get pods -n sunbird` → works ✓

> Without VPN: `kubectl` fails — AKS API server has no public endpoint.

---

## Step 9 — Run the Deployment

Go to **Actions → Spark Platform Infra And Deploy → Run workflow**.

Fill in the inputs:

| Input | Description |
|-------|-------------|
| **environment** | Your environment name (e.g. `demo`) |
| **config_branch** | Branch of your private repo (default: `main`) |
| **source_branch** | Branch of sunbird-spark-installer (default: `main`) |

Run in three phases:

### Phase 1 — Infrastructure

Enable and run:
- `1️⃣ Create Terraform backend`
- `3️⃣ Create infrastructure resources`

Creates AKS (private), VNet, storage, Key Vault. Workflow auto-commits `global-cloud-values.yaml` and `tf.sh` back to `configs/demo/`.

After Phase 1, **add a DNS A record** for your domain pointing to the load balancer public IP shown in the workflow output.

### Phase 2 — Deploy Helm Bundles

Enable `5️⃣ Install Helm components`, mode: `all`.

Deploys all 7 building blocks: monitoring → edbb → learnbb → knowledgebb → obsrvbb → inquirybb → additional.

> First run takes 25–40 minutes as container images are pulled.

### Phase 3 — Finalise the Platform

Run in order:
- `7️⃣ Restart workloads using keycloak keys`
- `8️⃣ Configure certificate keys`
- `9️⃣ DNS mapping`
- `🔟 Generate Postman environment file`
- `1️⃣1️⃣ Run post-install`
- `1️⃣2️⃣ Create client forms`

---

## Deploying Specific Helm Charts

Use when upgrading one or more services without running the full bundle.

### Via GitHub Actions

1. Enable `5️⃣ Install Helm components`
2. Set `helm_mode` to `selective`
3. Enter chart names in `specific_charts` (space-separated, e.g. `lern keycloak`)
4. Check **exactly one** bundle checkbox

### Via Manual Command

```bash
cd opentofu/azure/<env-name>
./install.sh install_service <bundle> <chart1> <chart2>
```

### Available Charts per Bundle

| Bundle | Targetable Charts |
|--------|-------------------|
| `edbb` | `kafka` `yugabyte` `router` `nginx-private-ingress` `nginx-public-ingress` `echo` `player` `kong` `kong-apis` `kong-consumers` `knowledgemw` `secor` |
| `learnbb` | `kafka` `elasticsearch` `yugabyte` `lern` `keycloak` `keycloak-kids-keys` `flink` `adminutil` `cert` `certificateapi` `certificatesign` `certregistry` `registry` |
| `knowledgebb` | `elasticsearch` `kafka` `yugabyte` `janusgraph` `knowlg` `search` `flink` |
| `obsrvbb` | `yugabyte` `superset` |
| `additional` | `volume-autoscaler` `nlweb` `nlwebflink` `kafka` |

---

## Step 10 (Optional) — Deploy Addons

Go to **Actions → Spark Platform Addons → Run workflow**.

| Addon | Steps |
|-------|-------|
| DIAL | Run `1️⃣ Run DIAL addon OpenTofu` first, then `2️⃣ → DIAL`. Set `deployed_dial_addon: "true"` in `global-values.yaml`. |
| Discussion Forum | Enable `2️⃣ → Discussion Forum` |
| Video Stream Generator | Enable `2️⃣ → Video Stream Generator` |

---

## Auto-Generated Files Reference

| File | Created by |
|------|-----------|
| `configs/demo/global-cloud-values.yaml` | `create_tf_resources` |
| `configs/demo/tf.sh` | `create_tf_backend` |
| `configs/demo/env.json` | `generate_postman_env` |
| `configs/demo/addons/global-cloud-values.yaml` | DIAL infra step |

---

## GitHub Actions (OIDC Path)

Use this path if you prefer public AKS cluster with Azure OIDC authentication.

### OIDC Setup

Two service principals are needed:

#### Infra SP

```bash
bash $INSTALLER_PATH/private-repo-setup/scripts/setup-infra-sp.sh
```

Edit variables at top first. Creates `<building_block>-<env>-github-infra`. Prints `AZURE_INFRA_CLIENT_ID`.

#### Deploy SP

> Run after AKS cluster exists (after Phase 1 infra).

```bash
bash $INSTALLER_PATH/private-repo-setup/scripts/setup-deploy-sp.sh
```

Creates `<building_block>-<env>-github-deploy`. Prints `AZURE_DEPLOY_CLIENT_ID`.

#### GitHub Secrets for OIDC

| Secret | Source |
|--------|--------|
| `ANSIBLE_VAULT_PASSWORD` | Vault password |
| `AZURE_INFRA_CLIENT_ID` | From setup-infra-sp.sh |
| `AZURE_DEPLOY_CLIENT_ID` | From setup-deploy-sp.sh |
| `AZURE_TENANT_ID` | Azure AD → Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure Portal → Subscriptions |

---

## Troubleshooting

**Runner not showing in GitHub**
Wait 5 minutes after VM creation — cloud-init takes time. Check logs: `ssh azureuser@<vm-ip>` → `cat /var/log/runner-setup.log`

**`ansible-vault: command not found`**
Run `pip install ansible`.

**`global-cloud-values.yaml not found` warning during deploy**
Expected on first run before Phase 1 completes. Finish `create_tf_resources` first.

**kubectl fails after VPN connect**
Ensure route `10.0.0.0/8` is added in Pritunl server settings. Reconnect VPN after adding route.

**AKS credentials step fails — cluster not found**
Ensure `global.building_block` matches what was used during infra. Cluster name is `{building_block}-{environment}`.

**Helm install times out**
Re-run the same bundle — `helm upgrade --install` is idempotent.

**DNS mapping times out**
Add A record manually and re-run from `9️⃣ dns_mapping`.
