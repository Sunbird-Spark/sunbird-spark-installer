#!/bin/bash
set -euo pipefail

###############################################################
# GCP VM Setup - Sunbird Spark Installer VM
#
# GCP equivalent of setup-installer-vm.sh (Azure). This script:
# 1. Creates a GCE VM with an attached (dedicated) service account
# 2. Creates a custom least-privilege IAM role and binds it, project-scoped
# 3. If VPN_ENABLED=true: installs Pritunl VPN + WireGuard via startup-script
#    If VPN_ENABLED=false: skips VPN (use Identity-Aware Proxy / `gcloud compute ssh`
#    for private access instead — GCP's equivalent of Azure Bastion)
# 4. Registers GitHub Actions self-hosted runner via startup-script
#
# Run ONCE per environment from owner's laptop.
# After this, all infra + deployments run via GitHub Actions.
#
# NOTE: the VM lives in the project's default VPC network, deliberately kept
# separate from whatever the OpenTofu network module creates for GKE later —
# that module always creates its VPC unconditionally (create_network isn't
# actually wired to a conditional yet), so reusing its intended name here
# would collide with `create_tf_resources` on first apply.
###############################################################

# ── CONFIGURE THESE BEFORE RUNNING ──────────────────────────────────────────
PROJECT_ID=""             # GCP project ID (gcloud config get-value project)
BUILDING_BLOCK=""         # Must match global.building_block in global-values.yaml (e.g. "ed")
ENVIRONMENT=""            # Must match configs/ folder name (e.g. "dev")
ZONE=""                   # GCP zone (e.g. "asia-south1-a") — must match global.zone
GITHUB_ORG=""             # GitHub org name (e.g. "Sunbird-Spark")
GITHUB_REPO=""            # GitHub repo name for repo-level runner, or leave empty for org-level
GITHUB_RUNNER_TOKEN=""    # GitHub -> Settings -> Actions -> Runners -> New runner -> copy token (expires in 1 hour)
VPN_ENABLED="true"        # "true" = install Pritunl VPN (VM gets public IP); "false" = IAP tunnel (no public IP on VM)
# ─────────────────────────────────────────────────────────────────────────────

# ── Validate inputs ────────────────────────────────────────────────────────
for var in PROJECT_ID BUILDING_BLOCK ENVIRONMENT ZONE GITHUB_ORG GITHUB_RUNNER_TOKEN; do
  if [ -z "${!var}" ]; then
    echo "❌ ERROR: $var is not set. Edit the variables at the top of this script."
    exit 1
  fi
done

REGION=$(echo "$ZONE" | sed 's/-[a-z]$//')

# ── VM config ──────────────────────────────────────────────────────────────
VM_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-runner"
VM_MACHINE_TYPE="e2-small"
VM_IMAGE_FAMILY="ubuntu-2204-lts"
VM_IMAGE_PROJECT="ubuntu-os-cloud"
VM_ADMIN_USER="ubuntu"
# GCP service account IDs must be 6-30 chars, lowercase letters/digits/hyphens, start with a letter
SA_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-runner"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
CUSTOM_ROLE_ID=$(echo "${BUILDING_BLOCK}_${ENVIRONMENT}_runner_role" | tr '-' '_')
FIREWALL_TAG="${VM_NAME}"

# ── Step 1: Set project ────────────────────────────────────────────────────
gcloud config set project "$PROJECT_ID" >/dev/null
echo "✓ Project: $PROJECT_ID"

# ── Step 2: Enable required APIs ────────────────────────────────────────────
gcloud services enable compute.googleapis.com iam.googleapis.com \
  container.googleapis.com cloudresourcemanager.googleapis.com >/dev/null
echo "✓ Required APIs enabled"

# ── Step 3: Create dedicated service account for the runner VM ────────────
if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
  echo "✓ Service account already exists: $SA_EMAIL"
else
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name "Sunbird-Spark ${BUILDING_BLOCK}-${ENVIRONMENT} runner VM" >/dev/null
  echo "✓ Service account created: $SA_EMAIL"
  echo "  Waiting for IAM to propagate (10s)..."
  sleep 10
fi

# ── Step 4: Create least-privilege custom role ─────────────────────────────
ROLE_YAML_FILE=$(mktemp)
cat > "$ROLE_YAML_FILE" <<EOF
title: "${BUILDING_BLOCK}-${ENVIRONMENT} runner role"
description: "Least-privilege role for the Sunbird-Spark runner VM. Lets OpenTofu manage GKE, networking, storage, service accounts, and IAM inside the project."
stage: "GA"
includedPermissions:
- resourcemanager.projects.get
- compute.instances.get
- compute.networks.get
- compute.networks.create
- compute.networks.update
- compute.networks.delete
- compute.networks.list
- compute.subnetworks.get
- compute.subnetworks.create
- compute.subnetworks.update
- compute.subnetworks.delete
- compute.subnetworks.list
- compute.subnetworks.use
- compute.routers.get
- compute.routers.create
- compute.routers.update
- compute.routers.delete
- compute.firewalls.get
- compute.firewalls.create
- compute.firewalls.update
- compute.firewalls.delete
- compute.firewalls.list
- compute.globalOperations.get
- compute.regionOperations.get
- compute.zoneOperations.get
- container.clusters.get
- container.clusters.create
- container.clusters.update
- container.clusters.delete
- container.clusters.list
- container.operations.get
- storage.buckets.get
- storage.buckets.create
- storage.buckets.update
- storage.buckets.delete
- storage.buckets.list
- storage.objects.get
- storage.objects.create
- storage.objects.update
- storage.objects.delete
- storage.objects.list
- iam.serviceAccounts.get
- iam.serviceAccounts.create
- iam.serviceAccounts.update
- iam.serviceAccounts.delete
- iam.serviceAccounts.list
- iam.serviceAccounts.actAs
- iam.serviceAccountKeys.get
- iam.serviceAccountKeys.create
- iam.serviceAccountKeys.delete
- iam.roles.get
- iam.roles.create
- iam.roles.update
- iam.roles.delete
- iam.roles.list
- resourcemanager.projects.getIamPolicy
- resourcemanager.projects.setIamPolicy
EOF

if gcloud iam roles describe "$CUSTOM_ROLE_ID" --project "$PROJECT_ID" &>/dev/null; then
  gcloud iam roles update "$CUSTOM_ROLE_ID" --project "$PROJECT_ID" --file "$ROLE_YAML_FILE" >/dev/null
  echo "✓ Custom role updated: $CUSTOM_ROLE_ID"
else
  gcloud iam roles create "$CUSTOM_ROLE_ID" --project "$PROJECT_ID" --file "$ROLE_YAML_FILE" >/dev/null
  echo "✓ Custom role created: $CUSTOM_ROLE_ID"
fi
rm -f "$ROLE_YAML_FILE"

# Bind the custom role to the runner's service account, project-scoped
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role "projects/${PROJECT_ID}/roles/${CUSTOM_ROLE_ID}" \
  --condition=None >/dev/null
echo "✓ Custom role bound to service account"

# Also bind GKE cluster admin (equivalent of Azure's "AKS Cluster Admin Role")
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:${SA_EMAIL}" \
  --role "roles/container.admin" \
  --condition=None >/dev/null
echo "✓ roles/container.admin bound to service account"

# ── Step 5: Build GitHub runner URL ─────────────────────────────────────────
if [ -n "$GITHUB_REPO" ]; then
  GITHUB_URL="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}"
else
  GITHUB_URL="https://github.com/${GITHUB_ORG}"
fi

# ── Step 6: Generate setup script ───────────────────────────────────────────
# Generated once; used for both new VM (startup-script) and existing VM
# (re-run over `gcloud compute ssh`).
SETUP_SCRIPT=$(mktemp)
cat > "$SETUP_SCRIPT" <<SETUPSCRIPT
#!/bin/bash
set -e
LOG=/var/log/runner-setup.log
exec > >(tee -a \$LOG) 2>&1
echo "=== Setup start \$(date) ==="
VPN_ENABLED="${VPN_ENABLED}"

# Base packages (startup-script may not have run apt-get update yet)
apt-get update -qq
apt-get install -y -qq unzip jq curl git openssl ca-certificates gnupg apt-transport-https

# gcloud CLI (most GCE Ubuntu images already have it; install if missing)
if ! command -v gcloud &>/dev/null; then
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  apt-get update -qq && apt-get install -y -qq google-cloud-cli
fi

# kubectl
KUBECTL_VER=\$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -sLO "https://dl.k8s.io/release/\${KUBECTL_VER}/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# gke-gcloud-auth-plugin (required by kubectl against GKE with newer auth flow)
apt-get install -y -qq google-cloud-cli-gke-gcloud-auth-plugin || true

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# OpenTofu
TOFU_VERSION="1.11.4"
curl -sLO "https://github.com/opentofu/opentofu/releases/download/v\${TOFU_VERSION}/tofu_\${TOFU_VERSION}_linux_amd64.zip"
unzip -qo tofu_\${TOFU_VERSION}_linux_amd64.zip -d /usr/local/bin/ && rm tofu_\${TOFU_VERSION}_linux_amd64.zip

# Terragrunt
curl -sLo /usr/local/bin/terragrunt "https://github.com/gruntwork-io/terragrunt/releases/download/v0.77.5/terragrunt_linux_amd64"
chmod +x /usr/local/bin/terragrunt

# yq
curl -sLo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v4.44.1/yq_linux_amd64"
chmod +x /usr/local/bin/yq

# rclone
curl https://rclone.org/install.sh | bash || true

# Docker
curl -fsSL https://get.docker.com | bash || true
usermod -aG docker ${VM_ADMIN_USER}

# VPN (Pritunl + WireGuard) - only when VPN_ENABLED=true
if [ "\$VPN_ENABLED" = "true" ]; then
  echo "==> Installing Pritunl + WireGuard..."
  set +e
  apt-get install -y wireguard
  echo "deb https://repo.pritunl.com/stable/apt jammy main" > /etc/apt/sources.list.d/pritunl.list
  apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv 7568D9BB55FF9E5287D586017AE645C0CF8E292A
  curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-6.0.gpg
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-6.0.list
  apt-get update -qq 2>&1 | tee /tmp/pritunl-apt-update.log
  apt-get install -y pritunl mongodb-org 2>&1 | tee /tmp/pritunl-install.log
  PRITUNL_INSTALL_STATUS=\$?
  set -e
  if [ \$PRITUNL_INSTALL_STATUS -ne 0 ]; then
    echo "ERROR: Pritunl install failed. Reason:"
    tail -20 /tmp/pritunl-install.log
  else
    pritunl set-mongodb mongodb://localhost:27017/pritunl
    systemctl enable mongod && systemctl start mongod
    echo "Waiting for MongoDB..."
    until mongosh --eval "db.runCommand({ping:1})" &>/dev/null; do sleep 3; done
    echo "MongoDB ready"
    systemctl enable pritunl && systemctl start pritunl
    sleep 15
    DEFAULT_PASS=\$(pritunl default-password | grep -i '^\s*password:' | awk '{print \$2}' | tr -d '"')
    echo "  Pritunl credentials → username: pritunl  password: \${DEFAULT_PASS}"
    echo "pritunl:\${DEFAULT_PASS}" > /tmp/pritunl-creds
    echo "  Org, server, and users are NOT created automatically — set them up via the Pritunl Admin UI (see private-repo-setup/README.md)."
  fi
else
  echo "VPN_ENABLED=false - skipping Pritunl."
fi

# GitHub Actions Runner
echo "==> Installing GitHub Actions Runner..."
set +e
RUNNER_VERSION=\$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
mkdir -p /home/${VM_ADMIN_USER}/actions-runner && cd /home/${VM_ADMIN_USER}/actions-runner
curl -sLO "https://github.com/actions/runner/releases/download/v\${RUNNER_VERSION}/actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz" 2>&1 | tee /tmp/runner-download.log
tar xzf "actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz"
rm "actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz"
chown -R ${VM_ADMIN_USER}:${VM_ADMIN_USER} /home/${VM_ADMIN_USER}/actions-runner
sudo -u ${VM_ADMIN_USER} ./config.sh \
  --url "${GITHUB_URL}" \
  --token "${GITHUB_RUNNER_TOKEN}" \
  --name "\$(hostname)" \
  --labels "self-hosted,gcp,linux" \
  --unattended --replace 2>&1 | tee /tmp/runner-config.log
RUNNER_CONFIG_STATUS=\$?
set -e
if [ \$RUNNER_CONFIG_STATUS -ne 0 ]; then
  echo "ERROR: GitHub Actions runner registration failed. Reason:"
  tail -20 /tmp/runner-config.log
else
  ./svc.sh install ${VM_ADMIN_USER} && ./svc.sh start
  echo "✓ GitHub Actions runner registered and started."
fi
echo "=== Setup complete \$(date) ==="
echo "SUCCESS" > /tmp/setup-status
SETUPSCRIPT

# ── Step 7: Create firewall rules (VPN only) ────────────────────────────────
if [ "$VPN_ENABLED" = "true" ]; then
  gcloud compute firewall-rules create "${FIREWALL_TAG}-allow-pritunl-vpn" \
    --network default --direction INGRESS --action ALLOW \
    --rules udp:1194 --target-tags "$FIREWALL_TAG" --source-ranges 0.0.0.0/0 \
    2>/dev/null || echo "✓ Firewall rule allow-pritunl-vpn already exists (skipped)"

  gcloud compute firewall-rules create "${FIREWALL_TAG}-allow-pritunl-ui" \
    --network default --direction INGRESS --action ALLOW \
    --rules tcp:443 --target-tags "$FIREWALL_TAG" --source-ranges 0.0.0.0/0 \
    2>/dev/null || echo "✓ Firewall rule allow-pritunl-ui already exists (skipped)"

  echo "✓ Firewall rules ensured (UDP 1194, TCP 443)"
else
  echo "✓ VPN disabled - no firewall rules added (access via \`gcloud compute ssh\` / IAP tunnel)"
fi

# ── Step 8: Create VM or run setup on existing VM ──────────────────────────
VM_EXISTED="false"
if gcloud compute instances describe "$VM_NAME" --zone "$ZONE" &>/dev/null; then
  VM_EXISTED="true"
  echo "✓ VM already exists: $VM_NAME — re-running setup over SSH (~10 min)..."
  gcloud compute scp "$SETUP_SCRIPT" "${VM_ADMIN_USER}@${VM_NAME}:/tmp/setup.sh" --zone "$ZONE"
  gcloud compute ssh "${VM_ADMIN_USER}@${VM_NAME}" --zone "$ZONE" \
    --command "sudo bash /tmp/setup.sh"
  SETUP_STATUS=$(gcloud compute ssh "${VM_ADMIN_USER}@${VM_NAME}" --zone "$ZONE" \
    --command "cat /tmp/setup-status 2>/dev/null || echo UNKNOWN")
  if [ "$SETUP_STATUS" = "SUCCESS" ]; then
    echo "✓ Setup completed successfully on existing VM."
  else
    echo "ERROR: Setup failed or output was truncated. Check full log:"
    echo "  gcloud compute ssh ${VM_ADMIN_USER}@${VM_NAME} --zone ${ZONE} --command 'sudo tail -100 /var/log/runner-setup.log'"
    exit 1
  fi
  rm -f "$SETUP_SCRIPT"
else
  echo "Creating VM... (this takes ~1 minute)"
  if [ "$VPN_ENABLED" = "true" ]; then
    NETWORK_TIER_ARGS=(--network-tier=STANDARD)
  else
    NETWORK_TIER_ARGS=(--no-address)
  fi

  gcloud compute instances create "$VM_NAME" \
    --zone "$ZONE" \
    --machine-type "$VM_MACHINE_TYPE" \
    --image-family "$VM_IMAGE_FAMILY" \
    --image-project "$VM_IMAGE_PROJECT" \
    --service-account "$SA_EMAIL" \
    --scopes "cloud-platform" \
    --tags "$FIREWALL_TAG" \
    --metadata-from-file startup-script="$SETUP_SCRIPT" \
    "${NETWORK_TIER_ARGS[@]}" >/dev/null

  rm -f "$SETUP_SCRIPT"
  echo "✓ VM created: $VM_NAME"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo "Runner VM setup complete."
echo "VM: $VM_NAME"
if [ "$VPN_ENABLED" = "true" ]; then
  VM_IP=$(gcloud compute instances describe "$VM_NAME" --zone "$ZONE" \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
  echo "Public IP: $VM_IP"
  echo "SSH: gcloud compute ssh ${VM_ADMIN_USER}@${VM_NAME} --zone ${ZONE}"
else
  echo "Public IP: none (private VM, access via \`gcloud compute ssh\` over IAP tunnel)"
fi

if [ "$VM_EXISTED" = "true" ]; then
  echo "Setup complete. Runner and VPN are ready."
else
  echo "startup-script running in background (~10 min). Check:"
  echo "  gcloud compute ssh ${VM_ADMIN_USER}@${VM_NAME} --zone ${ZONE} --command 'sudo tail -f /var/log/runner-setup.log'"
fi

echo "Runner: https://github.com/${GITHUB_ORG}/${GITHUB_REPO:+${GITHUB_REPO}/}settings/actions/runners"

if [ "$VPN_ENABLED" = "true" ]; then
  PRITUNL_CREDS=$(gcloud compute ssh "${VM_ADMIN_USER}@${VM_NAME}" --zone "$ZONE" \
    --command "cat /tmp/pritunl-creds 2>/dev/null || echo ''" 2>/dev/null || echo "")
  PRITUNL_PASS=$(echo "$PRITUNL_CREDS" | cut -d: -f2)
  echo "Pritunl VPN: https://${VM_IP}"
  echo "Pritunl username: pritunl"
  if [ -n "$PRITUNL_PASS" ]; then
    echo "Pritunl password: ${PRITUNL_PASS}"
  else
    echo "Pritunl password: gcloud compute ssh ${VM_ADMIN_USER}@${VM_NAME} --zone ${ZONE} --command 'sudo pritunl default-password'"
  fi
fi
