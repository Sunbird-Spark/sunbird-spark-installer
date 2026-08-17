# Sunbird Spark — Private Deployment Repository Setup

This guide walks through creating a **private GitHub repository** that holds your environment configuration (encrypted) and GitHub Actions workflows to deploy Sunbird Spark using `sunbird-spark-installer` as the source.

> Throughout this guide, `demo` is used as the environment name. Replace it with your own (e.g. `production`, `staging`, `uat`).

---

## Choose Your Deployment Path

| Path | When to use |
|------|-------------|
| **Self-hosted runner + Managed Identity** *(recommended)* | Private AKS cluster, no Azure credentials stored anywhere, developer access via VPN or Bastion |
| **GitHub Actions (OIDC)** | Public AKS cluster, Azure OIDC auth via service principals |
| **Manual via Azure VM** | Quick start — SSH into a VM and run `install.sh` directly |

This guide covers the **Self-hosted runner** path, which has two developer-access variants controlled by `vpn_enabled` in `global-values.yaml` (see [opentofu/azure/README.md](../opentofu/azure/README.md#private-cluster--access-options) for the full decision tree):

| `vpn_enabled` | Access method | Guide |
|---|---|---|
| `true` (default) | Pritunl VPN — WireGuard-compatible client on developer laptop | **This guide**, below |
| `false` | Azure Bastion — browser-based SSH through Azure Portal, no VPN client | [BASTION-SETUP.md](BASTION-SETUP.md) |

For the OIDC path, see [OIDC Setup](#github-actions-oidc-path).

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

2. Clone it locally and create the folder structure — stay on the default branch (`main`) for this step:

```bash
git clone https://github.com/org-name/spark-devops.git
cd spark-devops
mkdir -p .github/workflows configs/demo
```

---

## Step 2 — Copy Workflow Templates

Workflow files must live on `main` (the repo's default branch) — GitHub Actions only lists `workflow_dispatch` workflows for manual triggering if they exist there. They are **not** per-environment.

```bash
INSTALLER_PATH=/path/to/sunbird-spark-installer

cp $INSTALLER_PATH/private-repo-setup/.github/workflows/sunbird-spark-platform.yaml .github/workflows/
cp $INSTALLER_PATH/private-repo-setup/.github/workflows/sunbird-spark-addons.yaml .github/workflows/

git add .github/workflows/
git commit -m "Add Sunbird Spark deployment workflows"
git push origin main
```

---

## Step 3 — Prepare `global-values.yaml`

Create a **branch for this environment** first — one per environment, named to match the `configs/<env>` folder (e.g. `demo`, `dev`, `staging`, `production`). Env config is **not** committed to `main`; only the workflow files (Step 2) live there.

```bash
git checkout -b demo   # one branch per environment

cp $INSTALLER_PATH/opentofu/azure/template/global-values.yaml configs/demo/global-values.yaml
```

Open the file and fill in all required fields — see the root [README.md](../README.md) for the full field reference. Only `vpn_enabled` is relevant here; VM sizing, GitHub runner registration, and Pritunl org/network/users are **not** set in this file.

Also edit the variables at the top of `setup-installer-vm.sh` before running it in Step 5 below:
```bash
VM_SIZE="Standard_B2s"
VM_ADMIN_USER="azureuser"
GITHUB_RUNNER_TOKEN=""   # GitHub → Settings → Actions → Runners → New runner
GITHUB_ORG=""
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
git push -u origin demo   # push the env branch created in Step 3, not main
```

> Confirm encryption: the file should start with `$ANSIBLE_VAULT;1.1;AES256`. Never commit it unencrypted.

---

## Step 5 — Create the Runner VM (One Time)

Just run the script below — it reads `VPN_ENABLED` and installs Pritunl VPN + WireGuard when `true`, or skips it when `false`. Azure Bastion itself isn't created here — it gets created automatically by `install.sh create_tf_resources` in Step 9, when `vpn_enabled: false` in `global-values.yaml`. Developer access afterward differs by path: Step 8 covers VPN; for Bastion, connect via Azure Portal → your resource group → `<bb>-<env>-bastion` → **Connect** (see [BASTION-SETUP.md](BASTION-SETUP.md) for details).

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
- Starts Pritunl + prints its admin credentials — org, server, and users are **not** created automatically; set these up via the Pritunl Admin UI (see the "Pritunl Admin" section below)
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
3. Install [Pritunl Client](https://client.pritunl.com/) (Windows / Mac / Linux) — it imports Pritunl-generated WireGuard profiles natively, no separate WireGuard app needed
4. Download your profile from the Pritunl web UI → import into Pritunl Client → Connect
5. `kubectl get pods -n sunbird` → works ✓

> Without VPN: `kubectl` fails — AKS API server has no public endpoint.

### Pritunl Admin — Adding Users, Orgs, and Passwords

Required firewall/NSG ports (already opened by the setup script, listed here for reference):

| Port | Protocol | Purpose |
|------|----------|---------|
| 443  | TCP      | Pritunl admin/user web UI (`https://<vm-public-ip>`) |
| 1194 | UDP      | WireGuard VPN tunnel traffic |

**Add a new VPN user (full flow):**

1. Log into `https://<vm-public-ip>` as admin. While resetting the admin password, Pritunl also prompts you to enable two-factor authentication (Google Authenticator) — set this up if prompted.
2. **Organizations** → **Add Organization** → enter a name → **Add**
3. **Servers** → **Add Server** → configure as WireGuard, port `1194` → **Add**, then select the server → **Attach Organization** → pick the org → **Operation** → **Restart**
4. Go to **Users** → select the organization
5. Click **Add User** → enter name + email → **Add**
6. Send the new user the link to this doc — they follow the Step 8 flow above to download their own profile and connect

> Steps 2-3 are one-time setup — the install script starts Pritunl but does **not** create the org or server automatically, so you'll need to do this once per environment.

> VPN users authenticate via their downloaded WireGuard profile (key-based), not a password — there's nothing to "set" for a user's VPN login.

**Reset the Pritunl admin password:**

- Via CLI (SSH into the runner VM):
  ```bash
  sudo pritunl reset-password
  ```
  Prints a new admin password directly in the terminal — copy it immediately, it's only shown once.
- Via Web UI (if already logged in): **Settings** → **Administrators** → select the admin account → set new password → **Save**

---

## Step 9 — Run the Deployment

Go to **Actions → Spark Platform Infra And Deploy → Run workflow**.

Fill in the inputs:

| Input | Description |
|-------|-------------|
| **environment** | Your environment name (e.g. `demo`) |
| **config_branch** | Branch of your private repo holding this environment's config — the branch you created in Step 3 (e.g. `demo`), **not** `main` |
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

Deploys all 6 building blocks: monitoring → edbb → learnbb → knowledgebb → obsrvbb → additional.

> First run takes 25–40 minutes as container images are pulled.

### Phase 3 — Finalise the Platform

Run in order:
- `7️⃣ Restart workloads using keycloak keys`
- `8️⃣ Configure certificate keys`
- `9️⃣ DNS mapping`
- `🔟 Generate Postman environment file`
- `1️⃣1️⃣ Run post-install`
- `1️⃣2️⃣ Create client forms`

### Manual Alternative (SSH into the Runner VM)

Every step above is just a GitHub Actions wrapper around `install.sh` functions. You can run the exact same deployment by SSHing into the runner VM (or the Bastion-connected VM) and calling `install.sh` directly — useful for debugging, re-running a single failed step, or environments without the GitHub Actions workflow set up.

```bash
cd sunbird-spark-installer/opentofu/azure/<env-name>

# Phase 1 — Infrastructure
./install.sh create_tf_backend
./install.sh create_tf_resources

# Phase 2 — Deploy Helm Bundles
./install.sh install_helm_components

# Phase 3 — Finalise the Platform
./install.sh restart_workloads_using_keys
./install.sh certificate_config
./install.sh dns_mapping
./install.sh generate_postman_env
./install.sh run_post_install
./install.sh migrate_forms
```

Functions can also be chained in one call: `./install.sh create_tf_backend create_tf_resources`. See `CLAUDE.md` for the full command reference.

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
