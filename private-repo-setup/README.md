# Setting Up a Private Deployment Repository for Sunbird Spark

This guide explains how to create your own **private GitHub repository** to deploy Sunbird Spark on Azure using GitHub Actions. The private repo holds your environment-specific configuration (encrypted) and the GitHub Actions workflows that orchestrate the full deployment using `sunbird-spark-installer` as the source.

## How to Set Up Your Private Repository

Setting up a private repository for Sunbird Spark deployment involves three main components working together:

1. **Your private config repository** — holds your environment configuration (encrypted with Ansible Vault) and the GitHub Actions workflows that run deployments
2. **The public `sunbird-spark-installer` repository** — the workflows clone this at runtime to get all Helm charts, OpenTofu modules, and deployment scripts; you never need to fork or modify it
3. **Azure OIDC authentication** — the workflows authenticate to Azure using federated credentials, so no Azure secrets are ever stored in GitHub

This guide covers **two deployment approaches** — choose the one that fits your team:

- **GitHub Actions (recommended)** — workflows run in the cloud on every trigger; no VM to manage; requires a private GitHub repo with encrypted config
- **Manual via Azure VM** — SSH into a dedicated VM and run `install.sh` directly; simpler setup with no CI/CD configuration needed

For GitHub Actions, the setup process at a glance:

1. Create a private GitHub repository and copy the template files from `private-repo-setup/` in this repo
2. Choose an environment name (e.g. `production`, `staging`, `uat`) — you'll use it as a folder name, GitHub environment name, and YAML config value
3. Fill in and encrypt `global-values.yaml` with your environment's credentials
4. Run the OIDC setup script once locally to create Azure service principals
5. Add 5 secrets to your GitHub Actions environment
6. Run the deployment workflows in 3 phases

For the VM approach, skip to [Alternative: Manual Deployment via Azure VM](#alternative-manual-deployment-via-azure-vm).

The diagram below shows how the two repositories work together at deploy time:

```
sunbird-spark-installer (public)          your-private-devops-repo (private)
├── helmcharts/                     ←───  workflows clone this at runtime
├── opentofu/azure/template/
└── scripts/                              configs/<env>/
                                          ├── global-values.yaml  ← you fill in (encrypted)
                                          ├── global-cloud-values.yaml  ← auto-generated
                                          ├── tf.sh  ← auto-generated
                                          └── env.json  ← auto-generated
```

> `<env>` throughout this guide is a placeholder for the environment name you choose. It can be anything — `production`, `staging`, `uat`, `demo`, etc. Whatever you choose, use it consistently across all steps.

---

## Prerequisites

Before you begin, have the following ready:

- **Azure subscription** with Owner or Contributor access
- **GitHub account or organization** where you'll create the private repo
- **Domain name** pointing (or to be pointed) to your Azure deployment
- **SSL/TLS certificate** — FullChain (certificate + CA bundle) and private key in PEM format
  - Or use Let's Encrypt (the installer manages this automatically — see `global-values.yaml`)
- **Google OAuth 2.0 credentials** — [Create here](https://developers.google.com/workspace/guides/create-credentials#oauth-client-id)
- **Google ReCAPTCHA v3 credentials** — [Create here](https://www.google.com/recaptcha/admin)
- **Email (SMTP) service** — SendGrid recommended. You need the API key and a verified sender email.
- **Azure CLI** installed locally (for running the OIDC setup script)

---

## Repository Structure

Your private repo will have this structure. Replace `<env>` with your chosen environment name — you can have multiple environment folders (e.g., `configs/staging/`, `configs/production/`) in the same repo.

```
your-spark-devops/                          ← your private GitHub repo
├── .github/
│   └── workflows/
│       ├── sunbird-spark-platform.yaml     ← main deployment workflow
│       └── sunbird-spark-addons.yaml       ← addons workflow (optional)
├── configs/
│   └── <env>/                             ← your environment name (you decide)
│       ├── global-values.yaml             ← YOU create this (encrypted)
│       ├── global-cloud-values.yaml       ← auto-generated after infra run
│       ├── tf.sh                          ← auto-generated after backend creation
│       └── env.json                       ← auto-generated after post-install
└── scripts/
    └── setup-azure-oidc.sh                ← run once locally to set up Azure auth
```

---

## Step 1: Create the Private GitHub Repository

1. Create a new **private** repository in your GitHub account or organization. Name it anything (e.g., `my-spark-devops`, `sunbird-infra`, `spark-devops`).

2. Clone it locally:
   ```bash
   git clone https://github.com/your-org/your-spark-devops.git
   cd your-spark-devops
   ```

3. Create the directory structure (replace `<env>` with your chosen environment name):
   ```bash
   mkdir -p .github/workflows configs/<env> scripts
   ```

---

## Step 2: Copy the Template Files

From the `sunbird-spark-installer` repository, copy the template files into your private repo:

```bash
# From inside your private repo directory
INSTALLER_PATH=/path/to/sunbird-spark-installer

cp $INSTALLER_PATH/private-repo-setup/.github/workflows/sunbird-spark-platform.yaml .github/workflows/
cp $INSTALLER_PATH/private-repo-setup/.github/workflows/sunbird-spark-addons.yaml .github/workflows/
cp $INSTALLER_PATH/private-repo-setup/scripts/setup-azure-oidc.sh scripts/
cp $INSTALLER_PATH/private-repo-setup/scripts/setup-installer-vm.sh scripts/
chmod +x scripts/setup-azure-oidc.sh scripts/setup-installer-vm.sh
```

---

## Step 3: Prepare `global-values.yaml`

Copy the template config file from the installer and fill in your values:

```bash
cp $INSTALLER_PATH/opentofu/azure/template/global-values.yaml configs/<env>/global-values.yaml
```

Open `configs/<env>/global-values.yaml` and fill in the fields below.

### Required Fields

| Field | Description |
|-------|-------------|
| `global.building_block` | A short prefix for all your Azure resources (e.g., `"myorg"`). Lowercase letters only. |
| `global.env` | Short environment tag used inside the cluster (e.g., `"prod"`, `"stg"`). |
| `global.environment` | Environment name, 1–9 lowercase alphanumeric characters. **Must exactly match** your `configs/<env>/` folder name and the GitHub Actions environment name you'll create in Step 6. |
| `global.domain` | Your domain (e.g., `"sunbird.myorg.com"`). |
| `global.subscription_id` | Your Azure Subscription ID. |
| `global.cloud_storage_region` | Azure region for storage (e.g., `"eastus"`, `"centralindia"`). |
| `global.sunbird_google_captcha_site_key` | Google ReCAPTCHA v3 site key. |
| `global.google_captcha_private_key` | Google ReCAPTCHA v3 secret key. |
| `global.sunbird_google_oauth_clientId` | Google OAuth 2.0 client ID. |
| `global.sunbird_google_oauth_clientSecret` | Google OAuth 2.0 client secret. |
| `global.mail_server_from_email` | The "from" email address shown on outgoing emails. |
| `global.mail_server_password` | SMTP password. For SendGrid, this is the API key value. |
| `global.proxy_private_key` | SSL/TLS private key in PEM format (multiline — follow the commented example in the template). |
| `global.proxy_certificate` | SSL/TLS certificate chain in PEM format (fullchain: certificate + CA bundle). |

> **Using Let's Encrypt instead of a manual SSL cert?** Set `global.lets_encrypt_ssl: true` and provide `global.cert_notifications.email`. You can leave `proxy_private_key` and `proxy_certificate` blank — the installer manages them automatically.

### Passwords — Change from Insecure Defaults

| Field | Default | What to Set |
|-------|---------|-------------|
| `default_passwords.keycloak_password` | `"admin"` | A strong password. This is also used by `keycloak.keycloak_password` and `keycloak-kids-keys.KEYCLOAK_ADMIN_PASSWORD` via YAML anchors. |
| `default_passwords.grafana_admin_password` | `"prom-operator"` | A strong password for the Grafana dashboard. |
| `default_passwords.superset_admin_password` | `"admin"` | A strong password for the Superset dashboard. |
| `global.yugabyte.ysql.password` | `"yugabyte"` | A strong password for the YugabyteDB database. |

### Optional Fields

| Field | Description |
|-------|-------------|
| `global.sunbird_msg_91_auth` | MSG91 SMS API token — required for OTP delivery via SMS during user registration / password reset. Leave empty to disable. |
| `global.sunbird_msg_sender` | MSG91 sender ID. |
| `global.youtube_apikey` | YouTube Data API key — required if users upload content via YouTube URL. Leave empty to disable. |
| `global.cert_notifications.email` | Email address for SSL certificate renewal alerts. |
| `global.mail_from_certbot_notifications` | "From" address for Certbot SSL renewal notification emails. |

### Feature Flags

| Field | Default | Description |
|-------|---------|-------------|
| `deployed_dial_addon` | `"false"` | Set to `"true"` if you plan to deploy the DIAL addon (QR code content delivery). Enables DIAL-specific routing in the core services. |
| `enable_asset_enrichment` | `"false"` | Set to `"true"` to enable automatic asset metadata enrichment. |
| `global.lets_encrypt_ssl` | `false` | Set to `true` if using Let's Encrypt for SSL. |

### SMTP Defaults (Keep Unless Using a Different Provider)

| Field | Default |
|-------|---------|
| `global.mail_server_host` | `smtp.sendgrid.net` |
| `global.mail_server_port` | `"587"` |
| `global.mail_server_username` | `apikey` (SendGrid uses the literal string "apikey") |

---

## Step 4: Encrypt and Commit the Config

Install Ansible (needed for Vault encryption) and encrypt your config file:

```bash
pip install ansible

# Generate a strong vault password — save this somewhere safe (password manager)
# You'll add it to GitHub Secrets in Step 6
ansible-vault encrypt configs/<env>/global-values.yaml
# Enter a strong password when prompted — this becomes your ANSIBLE_VAULT_PASSWORD secret

# Commit the encrypted file (safe to commit — it's encrypted)
git add configs/<env>/global-values.yaml
git commit -m "Add encrypted environment config"
git push
```

> **Important:** Never commit the file unencrypted. The `$ANSIBLE_VAULT;1.1;AES256` header at the top of the file confirms it is encrypted.

---

## Step 5: Set Up Azure Authentication (OIDC)

The workflows authenticate to Azure using **OpenID Connect (OIDC) federated credentials** — no client secrets are stored. This is more secure than storing Azure credentials as GitHub secrets.

Edit the variables at the top of `scripts/setup-azure-oidc.sh`:

```bash
TENANT_ID=""           # Azure Portal → Azure Active Directory → Overview → Tenant ID
SUBSCRIPTION_ID=""     # Azure Portal → Subscriptions → your subscription → Subscription ID
BUILDING_BLOCK=""      # Must match global.building_block in global-values.yaml (e.g. "myorg")
ENVIRONMENT=""         # Must match your configs/<env>/ folder name
RESOURCE_GROUP=""      # The Azure resource group to create (e.g. "myorg-<env>")
GITHUB_REPO=""         # "your-org/your-spark-devops" (your private repo)
GITHUB_ENVIRONMENT=""  # Same as ENVIRONMENT
```

Then run it (requires `az` CLI and an active Azure login):

```bash
bash scripts/setup-azure-oidc.sh
```

The script will:
1. Create a custom Azure RBAC role with least-privilege permissions for OpenTofu
2. Create two Azure App Registrations with service principals:
   - `<building_block>-<env>-github-infra` — for infrastructure provisioning (AKS, storage, networking)
   - `<building_block>-<env>-github-deploy` — for Kubernetes deployments (kubectl, helm)
3. Set up OIDC federated trust so GitHub Actions can authenticate without storing any secrets
4. Print the client IDs and other values to add to GitHub Secrets

---

## Step 6: Configure GitHub Actions Environment and Secrets

1. In your private repo, go to **Settings → Environments → New environment**
2. Create an environment named exactly the same as your `configs/<env>/` folder name
3. Under that environment, add the following **Secrets** (Settings → Environments → `<env>` → Add secret):

| Secret Name | Where to Get It |
|-------------|----------------|
| `ANSIBLE_VAULT_PASSWORD` | The password you chose when running `ansible-vault encrypt` in Step 4 |
| `AZURE_INFRA_CLIENT_ID` | Printed by `setup-azure-oidc.sh` at the end |
| `AZURE_DEPLOY_CLIENT_ID` | Printed by `setup-azure-oidc.sh` at the end |
| `AZURE_TENANT_ID` | Your Azure AD Tenant ID (same value you put in the setup script) |
| `AZURE_SUBSCRIPTION_ID` | Your Azure Subscription ID (same value you put in the setup script) |

---

## Step 7: Update Environment Name in Workflows

In both `.github/workflows/sunbird-spark-platform.yaml` and `.github/workflows/sunbird-spark-addons.yaml`, find the `environment` input section and replace `your-env` with your actual environment name:

```yaml
# Before
options:
  - your-env   # Replace this with your environment name
default: your-env

# After (using your chosen environment name)
options:
  - <env>
default: <env>
```

Commit and push these changes:

```bash
git add .github/
git commit -m "Configure workflow environment name"
git push
```

---

## Step 8: Run the Deployment

Go to your private repo on GitHub → **Actions** → **Spark Platform Infra And Deploy** → **Run workflow**.

Run it in **three separate phases**:

### Phase 1 — Infrastructure

Enable these options and click **Run workflow**:
- `1️⃣ Create Terraform backend`
- `3️⃣ Create infrastructure resources`

This provisions your Azure resources: AKS cluster, VNet, storage accounts, Key Vault, managed identities. When complete, the workflow commits the auto-generated `global-cloud-values.yaml` and `tf.sh` back to `configs/<env>/`.

**After this phase:** Update your DNS — the workflow output will show the public IP of your load balancer. Add an A record for your domain pointing to that IP.

### Phase 2 — Deploy Helm Bundles

Enable these options:
- `5️⃣ Install Helm components`
- Mode: `all`

This deploys all 7 building blocks in order: monitoring → edbb → learnbb → knowledgebb → obsrvbb → inquirybb → additional.

> **Note:** This phase takes 25–40 minutes on first run as all container images are pulled.

### Phase 3 — Platform Finalisation

Enable these options (run in this order):
- `7️⃣ Restart workloads using keycloak keys`
- `8️⃣ Configure certificate keys`
- `9️⃣ DNS mapping` (waits up to 20 minutes for DNS propagation)
- `🔟 Generate Postman environment file`
- `1️⃣1️⃣ Run post-install`
- `1️⃣2️⃣ Create client forms`

When `generate_postman_env` completes, an encrypted `env.json` is committed to `configs/<env>/`.

---

## Step 9 (Optional): Deploy Addons

Go to **Actions** → **Spark Platform Addons** → **Run workflow**.

| Addon | What it adds |
|-------|-------------|
| DIAL | QR-code based content delivery. Run `1️⃣ Run DIAL addon OpenTofu` first, then `2️⃣ Deploy addon components → DIAL`. |
| Discussion Forum | NodeBB-based discussion forum. Enable `2️⃣ → Discussion Forum`. |
| Video Stream Generator | HLS video transcoding via Flink. Enable `2️⃣ → Video Stream Generator`. |

> If you plan to use DIAL, set `deployed_dial_addon: "true"` in `global-values.yaml` **before** running Phase 2 (Helm bundles), so the core services are configured for DIAL routing.

---

## Auto-Generated Files Reference

These files are created and committed automatically by the workflows. Do **not** create them manually:

| File | Created By | Description |
|------|-----------|-------------|
| `configs/<env>/global-cloud-values.yaml` | `create_tf_resources` step | Azure infrastructure outputs (storage keys, container names, cluster info) |
| `configs/<env>/tf.sh` | `create_tf_backend` step | OpenTofu backend environment variables |
| `configs/<env>/env.json` | `generate_postman_env` step | Postman environment with live API keys and URLs |
| `configs/<env>/addons/global-cloud-values.yaml` | DIAL infra step | DIAL storage container info |
| `configs/<env>/**/.terraform.lock.hcl` | `tofu init` | Provider version locks |

---

## Alternative: Manual Deployment via Azure VM

If you prefer to run the installer directly without GitHub Actions — SSH into a dedicated VM and execute `install.sh` yourself. This approach has fewer moving parts and does not require a private GitHub repository or encrypted config files.

### Step 1: Create the Installer VM

Edit the variables at the top of `scripts/setup-installer-vm.sh`:

```bash
TENANT_ID=""        # Azure Portal → Azure Active Directory → Overview → Tenant ID
SUBSCRIPTION_ID=""  # Azure Portal → Subscriptions → your subscription → Subscription ID
BUILDING_BLOCK=""   # Short prefix — must match global.building_block in global-values.yaml
ENVIRONMENT=""      # Environment name (e.g. "prod", "staging")
RESOURCE_GROUP=""   # Azure resource group to create the VM in (e.g. "myorg-prod")
LOCATION=""         # Azure region (e.g. "Central India", "East US")
```

Then run it locally (requires `az` CLI):

```bash
bash scripts/setup-installer-vm.sh
```

The script will create an Ubuntu 22.04 VM (`Standard_B2s`) with a system-assigned managed identity and the least-privilege RBAC role needed for OpenTofu. It prints the SSH command when done.

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

### Step 4: Clone the Installer and Prepare Your Environment

```bash
git clone https://github.com/Sunbird-Spark/sunbird-spark-installer.git
cd sunbird-spark-installer/opentofu/azure

# Create your environment folder
cp -r template <env>
cd <env>
```

Open `global-values.yaml` and fill in all required fields — refer to the [global-values.yaml fields table](#step-3-prepare-global-valuesyaml) above for the full list.

### Step 5: Authenticate to Azure from the VM

The VM's managed identity is already authorized to run OpenTofu. Log in using it:

```bash
az login --identity
```

### Step 6: Run the Installer

Run the full installation in one command:

```bash
time ./install.sh
```

Or run each phase individually, in order:

```bash
./install.sh create_tf_backend       # Initialise OpenTofu state backend
./install.sh create_tf_resources     # Provision AKS, storage, networking
./install.sh install_helm_components # Deploy all 7 Helm bundles
./install.sh restart_workloads_using_keys
./install.sh certificate_config
./install.sh dns_mapping
./install.sh generate_postman_env
./install.sh run_post_install
./install.sh create_client_forms
```

> For a full list of available commands, see the [Key Commands](../README.md#key-commands) section in the root README.

---

## Troubleshooting

**`ansible-vault: command not found`**
Install Ansible: `pip install ansible` or `pip3 install ansible`

**`OIDC token exchange failed` / Azure login fails in the workflow**
- Check that the GitHub repo name in `setup-azure-oidc.sh` exactly matches your private repo (case-sensitive)
- Check that the GitHub environment name in the script matches the environment name you created in Step 6
- Re-run `setup-azure-oidc.sh` — it is idempotent and will update existing credentials

**`global-cloud-values.yaml not found` warning during deploy**
This is expected on the first deploy before `create_tf_resources` has run. Complete Phase 1 first.

**AKS credentials step fails — cluster not found**
Ensure `global.building_block` in `global-values.yaml` matches what was used when the AKS cluster was created. The cluster name is `{building_block}-{environment}`.

**Helm install times out**
Some pods take time on first pull. Re-run the same bundle — `helm upgrade --install` is idempotent and will pick up where it left off.

**DNS mapping times out after 20 minutes**
Add the A record manually (the public IP is in the Phase 1 workflow logs) then re-run Phase 3 starting from `9️⃣ dns_mapping`.
