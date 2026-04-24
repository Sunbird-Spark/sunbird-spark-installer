# Setting Up a Private Deployment Repository for Sunbird Spark

This guide walks through creating a **private GitHub repository** that holds your environment configuration (encrypted) and the GitHub Actions workflows that deploy Sunbird Spark using `sunbird-spark-installer` as the source.

## How to Set Up Your Private Repository

Two deployment approaches are available:

- **GitHub Actions** — workflows in your private repo run deployments automatically. Requires encrypted config and Azure OIDC authentication.
- **Manual via Azure VM** — create a VM with the setup script, SSH in, and run `install.sh` directly. No CI/CD setup needed. Skip to [Alternative: Manual Deployment via Azure VM](#alternative-manual-deployment-via-azure-vm).

For GitHub Actions deployments, the workflow clones `sunbird-spark-installer` into the runner at runtime — your private repo only holds the encrypted config and workflow files.

> Throughout this guide `demo` is used as the environment name. Replace it with your own (e.g. `production`, `staging`, `uat`).

---

## Repository Structure

```
spark-devops/
├── .github/
│   └── workflows/
│       ├── sunbird-spark-platform.yaml     ← main deployment workflow
│       └── sunbird-spark-addons.yaml       ← addons workflow (optional)
└── configs/
    └── demo/                               ← your environment name (you decide)
        ├── global-values.yaml              ← YOU create this (encrypted)
        ├── global-cloud-values.yaml        ← auto-generated after infra run
        ├── tf.sh                           ← auto-generated after backend creation
        └── env.json                        ← auto-generated after post-install
```

---

## Step 1: Create the Private GitHub Repository

1. Create a new **private** repository in your GitHub account or organization.

2. Clone it locally:
   ```bash
   git clone https://github.com/org-name/spark-devops.git
   cd spark-devops
   ```

3. Create the directory structure:
   ```bash
   mkdir -p .github/workflows configs/demo
   ```

---

## Step 2: Copy the Template Files

```bash
INSTALLER_PATH=/path/to/sunbird-spark-installer

cp $INSTALLER_PATH/private-repo-setup/.github/workflows/sunbird-spark-platform.yaml .github/workflows/
cp $INSTALLER_PATH/private-repo-setup/.github/workflows/sunbird-spark-addons.yaml .github/workflows/
```

---

## Step 3: Prepare `global-values.yaml`

```bash
cp $INSTALLER_PATH/opentofu/azure/template/global-values.yaml configs/demo/global-values.yaml
```

Open `configs/demo/global-values.yaml` and fill in all required fields — refer to the root [README.md](../README.md) for the full field reference.

> `global.environment` **must exactly match** the `configs/` folder name and the GitHub Actions environment name in Step 6.

---

## Step 4: Encrypt and Commit the Config

```bash
pip install ansible

ansible-vault encrypt configs/demo/global-values.yaml
# Enter a strong password — save it securely. This becomes ANSIBLE_VAULT_PASSWORD in Step 6.

git add configs/demo/global-values.yaml
git commit -m "Add encrypted environment config"
git push
```

> The `$ANSIBLE_VAULT;1.1;AES256` header at the top of the file confirms it is encrypted. Never commit the file unencrypted.

---

## Step 5: Set Up Azure Authentication (OIDC)

The workflows authenticate to Azure using OIDC federated credentials — no client secrets stored in GitHub.

Edit the variables at the top of `$INSTALLER_PATH/private-repo-setup/scripts/setup-azure-oidc.sh`:

```bash
TENANT_ID=""           # Azure Portal → Azure Active Directory → Overview → Tenant ID
SUBSCRIPTION_ID=""     # Azure Portal → Subscriptions → Subscription ID
BUILDING_BLOCK=""      # Must match global.building_block in global-values.yaml
ENVIRONMENT=""         # Must match your configs/ folder name (e.g. "demo")
RESOURCE_GROUP=""      # Azure resource group (e.g. "myorg-demo")
GITHUB_REPO=""         # "org-name/spark-devops"
GITHUB_ENVIRONMENT=""  # Same as ENVIRONMENT
```

Run it (requires `az` CLI and Azure Owner access):

```bash
bash $INSTALLER_PATH/private-repo-setup/scripts/setup-azure-oidc.sh
```

The script creates two service principals with OIDC trust:
- `<building_block>-<env>-github-infra` — provisions AKS, storage, networking
- `<building_block>-<env>-github-deploy` — runs kubectl and helm

It prints the client IDs to add to GitHub Secrets at the end.

---

## Step 6: Configure GitHub Secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** in your private repo and add:

| Secret Name | Where to Get It |
|-------------|----------------|
| `ANSIBLE_VAULT_PASSWORD` | The password from Step 4 |
| `AZURE_INFRA_CLIENT_ID` | Printed by `setup-azure-oidc.sh` |
| `AZURE_DEPLOY_CLIENT_ID` | Printed by `setup-azure-oidc.sh` |
| `AZURE_TENANT_ID` | Your Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Your Azure Subscription ID |

---

## Step 7: Update Environment Name in Workflows

In both `.github/workflows/sunbird-spark-platform.yaml` and `sunbird-spark-addons.yaml`, replace `your-env` with your environment name:

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

## Step 8: Run the Deployment

Go to **Actions → Spark Platform Infra And Deploy → Run workflow** in your private repo.

Run in three phases:

### Phase 1 — Infrastructure

Enable and run:
- `1️⃣ Create Terraform backend`
- `3️⃣ Create infrastructure resources`

Provisions AKS, VNet, storage, Key Vault, and managed identities. The workflow commits auto-generated `global-cloud-values.yaml` and `tf.sh` back to `configs/demo/`.

**After this phase:** Add an A record for your domain pointing to the load balancer public IP shown in the workflow output.

### Phase 2 — Deploy Helm Bundles

Enable `5️⃣ Install Helm components`, mode: `all`.

Deploys all 7 building blocks: monitoring → edbb → learnbb → knowledgebb → obsrvbb → inquirybb → additional.

> First run takes 25–40 minutes as container images are pulled.

### Phase 3 — Platform Finalisation

Enable in order:
- `7️⃣ Restart workloads using keycloak keys`
- `8️⃣ Configure certificate keys`
- `9️⃣ DNS mapping`
- `🔟 Generate Postman environment file`
- `1️⃣1️⃣ Run post-install`
- `1️⃣2️⃣ Create client forms`

---

## Step 9 (Optional): Deploy Addons

Go to **Actions → Spark Platform Addons → Run workflow**.

| Addon | Steps |
|-------|-------|
| DIAL | Run `1️⃣ Run DIAL addon OpenTofu` first, then `2️⃣ → DIAL`. Set `deployed_dial_addon: "true"` in `global-values.yaml` before Phase 2. |
| Discussion Forum | Enable `2️⃣ → Discussion Forum`. |
| Video Stream Generator | Enable `2️⃣ → Video Stream Generator`. |

---

## Auto-Generated Files Reference

Do **not** create these manually — the workflows generate and commit them automatically:

| File | Created By |
|------|-----------|
| `configs/demo/global-cloud-values.yaml` | `create_tf_resources` |
| `configs/demo/tf.sh` | `create_tf_backend` |
| `configs/demo/env.json` | `generate_postman_env` |
| `configs/demo/addons/global-cloud-values.yaml` | DIAL infra step |
| `configs/demo/**/.terraform.lock.hcl` | `tofu init` |

---

## Alternative: Manual Deployment via Azure VM

SSH into a dedicated Azure VM and run `install.sh` directly. No private GitHub repository or encrypted config files needed.

### Step 1: Create the Installer VM

Edit the variables at the top of `$INSTALLER_PATH/private-repo-setup/scripts/setup-installer-vm.sh`:

```bash
TENANT_ID=""        # Azure Portal → Azure Active Directory → Overview → Tenant ID
SUBSCRIPTION_ID=""  # Azure Portal → Subscriptions → Subscription ID
BUILDING_BLOCK=""   # Must match global.building_block in global-values.yaml
ENVIRONMENT=""      # Environment name (e.g. "demo")
RESOURCE_GROUP=""   # Azure resource group (e.g. "myorg-demo")
LOCATION=""         # Azure region (e.g. "Central India", "East US")
```

Run it (requires `az` CLI and Azure Owner access):

```bash
bash $INSTALLER_PATH/private-repo-setup/scripts/setup-installer-vm.sh
```

Creates an Ubuntu 22.04 VM (`Standard_B2s`) with a system-assigned managed identity and the least-privilege RBAC role for OpenTofu. Prints the SSH command when done.

### Step 2: SSH into the VM

```bash
ssh -i ~/.ssh/<building_block>-<env>-installer-vm azureuser@<vm-public-ip>
```

### Step 3: Install Required CLI Tools on the VM

```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# OpenTofu
curl -fsSL https://get.opentofu.org/install-opentofu.sh | sudo sh -s -- --install-method standalone

# Terragrunt
sudo wget -qO /usr/local/bin/terragrunt \
  https://github.com/gruntwork-io/terragrunt/releases/download/v0.77.5/terragrunt_linux_amd64
sudo chmod +x /usr/local/bin/terragrunt

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# yq, jq, rclone
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
sudo apt-get install -y jq rclone

# Postman CLI
curl -o- "https://dl-cli.pstmn.io/install/linux64.sh" | sh
```

### Step 4: Clone and Prepare the Installer

```bash
git clone https://github.com/Sunbird-Spark/sunbird-spark-installer.git
cd sunbird-spark-installer/opentofu/azure

cp -r template demo
cd demo
```

Open `global-values.yaml` and fill in all required fields — refer to the root [README.md](../README.md) for the full field reference.

### Step 5: Authenticate Using the VM Managed Identity

```bash
az login --identity
```

### Step 6: Run the Installer

Full installation:

```bash
time ./install.sh
```

Or phase by phase:

```bash
./install.sh create_tf_backend
./install.sh create_tf_resources
./install.sh install_helm_components
./install.sh restart_workloads_using_keys
./install.sh certificate_config
./install.sh dns_mapping
./install.sh generate_postman_env
./install.sh run_post_install
./install.sh create_client_forms
```

---

## Troubleshooting

**`ansible-vault: command not found`**
Run `pip install ansible` or `pip3 install ansible`.

**Azure login fails in the workflow (OIDC token exchange failed)**
- Check that the GitHub repo name in `setup-azure-oidc.sh` exactly matches your private repo (case-sensitive)
- Check that the GitHub environment name matches the environment created in Step 6
- Re-run `setup-azure-oidc.sh` — it is idempotent

**`global-cloud-values.yaml not found` warning during deploy**
Expected on the first run before `create_tf_resources`. Complete Phase 1 first.

**AKS credentials step fails — cluster not found**
Ensure `global.building_block` matches what was used during infra creation. Cluster name is `{building_block}-{environment}`.

**Helm install times out**
Re-run the same bundle. `helm upgrade --install` is idempotent.

**DNS mapping times out**
Add the A record manually and re-run Phase 3 from `9️⃣ dns_mapping`.
