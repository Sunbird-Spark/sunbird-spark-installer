#!/bin/bash
set -euo pipefail

###############################################################
# Azure VM Setup - Sunbird Spark Installer VM
#
# This script:
# 1. Creates VNet + subnets + VM with UserAssigned managed identity
# 2. Creates a custom least-privilege role and assigns it
# 3. If VPN_ENABLED=true: installs Pritunl VPN + WireGuard via cloud-init
#    If VPN_ENABLED=false: skips VPN (Azure Bastion created by OpenTofu)
# 4. Registers GitHub Actions self-hosted runner via cloud-init
#
# Run ONCE per environment from owner's laptop.
# After this, all infra + deployments run via GitHub Actions.
###############################################################

# ── CONFIGURE THESE BEFORE RUNNING ──────────────────────────────────────────
TENANT_ID=""              # Azure AD Tenant ID (Azure Portal -> Azure Active Directory -> Overview)
SUBSCRIPTION_ID=""        # Azure Subscription ID (Azure Portal -> Subscriptions)
BUILDING_BLOCK=""         # Must match global.building_block in global-values.yaml (e.g. "ed")
ENVIRONMENT=""            # Must match configs/ folder name (e.g. "dev")
RESOURCE_GROUP=""         # Azure resource group (e.g. "ed-dev")
LOCATION=""               # Azure region (e.g. "Central India")
GITHUB_ORG=""             # GitHub org name (e.g. "Sunbird-Spark")
GITHUB_REPO=""            # GitHub repo name for repo-level runner, or leave empty for org-level
GITHUB_RUNNER_TOKEN=""    # GitHub -> Settings -> Actions -> Runners -> New runner -> copy token (expires in 1 hour)
VPN_ENABLED="true"        # "true" = install Pritunl VPN (VM gets public IP); "false" = Azure Bastion (no public IP on VM)
# Required only when VPN_ENABLED=true:
PRITUNL_VPN_NETWORK=""    # VPN client IP pool (e.g. "172.16.0.0/24")
PRITUNL_ORG_NAME=""       # Pritunl org name (e.g. "sunbird-spark")
# ─────────────────────────────────────────────────────────────────────────────

# ── Validate inputs ────────────────────────────────────────────────────────
for var in TENANT_ID SUBSCRIPTION_ID BUILDING_BLOCK ENVIRONMENT RESOURCE_GROUP LOCATION GITHUB_ORG GITHUB_RUNNER_TOKEN; do
  if [ -z "${!var}" ]; then
    echo "❌ ERROR: $var is not set. Edit the variables at the top of this script."
    exit 1
  fi
done

if [ "$VPN_ENABLED" = "true" ]; then
  for var in PRITUNL_VPN_NETWORK PRITUNL_ORG_NAME; do
    if [ -z "${!var}" ]; then
      echo "❌ ERROR: $var is required when VPN_ENABLED=true."
      exit 1
    fi
  done
fi

# ── VM config ──────────────────────────────────────────────────────────────
VM_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-runner"
VM_SIZE="Standard_B2s"
VM_IMAGE="Ubuntu2204"
VM_ADMIN_USER="azureuser"
IDENTITY_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-runner-identity"
CUSTOM_ROLE_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-runner-role"

# ── Step 1: Login ──────────────────────────────────────────────────────────
az login --tenant "$TENANT_ID"
az account set --subscription "$SUBSCRIPTION_ID"
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
echo "✓ Subscription: $SUBSCRIPTION_ID"

# ── Step 2: Create or reuse resource group ─────────────────────────────────
if az group exists --name "$RESOURCE_GROUP" -o tsv | grep -q "true"; then
  echo "✓ Resource group already exists: $RESOURCE_GROUP"
else
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
  echo "✓ Resource group created: $RESOURCE_GROUP"
fi

# ── Step 2b: Create VNet and subnets ──────────────────────────────────────
# Names must match OpenTofu network module: {building_block}-{environment}[-aks|-runner]
VNET_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}"
AKS_SUBNET_NAME="${VNET_NAME}-aks"
RUNNER_SUBNET_NAME="${VNET_NAME}-runner"

if az network vnet show --name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
  echo "✓ VNet already exists: $VNET_NAME"
else
  az network vnet create \
    --name "$VNET_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --address-prefixes "10.0.0.0/16" >/dev/null
  echo "✓ VNet created: $VNET_NAME (10.0.0.0/16)"
fi

if az network vnet subnet show --name "$AKS_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
  echo "✓ AKS subnet already exists: $AKS_SUBNET_NAME"
else
  az network vnet subnet create \
    --name "$AKS_SUBNET_NAME" \
    --vnet-name "$VNET_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --address-prefixes "10.0.0.0/20" \
    --service-endpoints "Microsoft.Sql" "Microsoft.Storage" >/dev/null
  echo "✓ AKS subnet created: $AKS_SUBNET_NAME (10.0.0.0/20)"
fi

if az network vnet subnet show --name "$RUNNER_SUBNET_NAME" --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
  echo "✓ Runner subnet already exists: $RUNNER_SUBNET_NAME"
else
  az network vnet subnet create \
    --name "$RUNNER_SUBNET_NAME" \
    --vnet-name "$VNET_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --address-prefixes "10.0.16.0/28" >/dev/null
  echo "✓ Runner subnet created: $RUNNER_SUBNET_NAME (10.0.16.0/28)"
fi

# ── Step 3: Create user-assigned managed identity ──────────────────────────
if az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
  echo "✓ Managed identity already exists: $IDENTITY_NAME"
else
  az identity create \
    --name "$IDENTITY_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" >/dev/null
  echo "✓ Managed identity created: $IDENTITY_NAME"
fi
IDENTITY_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
IDENTITY_OBJECT_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)

# ── Step 4: Create least-privilege custom role ─────────────────────────────
ROLE_JSON_FILE=$(mktemp)
cat > "$ROLE_JSON_FILE" <<EOF
{
  "Name": "${CUSTOM_ROLE_NAME}",
  "IsCustom": true,
  "Description": "Least-privilege role for Sunbird-Spark runner VM. Lets OpenTofu manage AKS, networking, storage, managed identity, and RBAC inside the target resource group.",
  "Actions": [
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/deployments/*",
    "Microsoft.ContainerService/managedClusters/*",
    "Microsoft.ContainerService/locations/*/read",
    "Microsoft.ContainerService/locations/operationresults/read",
    "Microsoft.ContainerService/locations/operations/read",
    "Microsoft.Network/virtualNetworks/*",
    "Microsoft.Network/networkSecurityGroups/*",
    "Microsoft.Network/routeTables/*",
    "Microsoft.Network/publicIPAddresses/*",
    "Microsoft.Network/loadBalancers/*",
    "Microsoft.Network/networkInterfaces/*",
    "Microsoft.Network/locations/operations/read",
    "Microsoft.Network/locations/operationResults/read",
    "Microsoft.Storage/storageAccounts/*",
    "Microsoft.Storage/locations/*/read",
    "Microsoft.Storage/operations/read",
    "Microsoft.ManagedIdentity/userAssignedIdentities/*",
    "Microsoft.Authorization/roleAssignments/read",
    "Microsoft.Authorization/roleAssignments/write",
    "Microsoft.Authorization/roleAssignments/delete",
    "Microsoft.Authorization/roleDefinitions/read",
    "Microsoft.Authorization/roleDefinitions/write",
    "Microsoft.Authorization/roleDefinitions/delete"
  ],
  "DataActions": [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/move/action",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action"
  ],
  "NotActions": [],
  "NotDataActions": [],
  "AssignableScopes": ["/subscriptions/${SUBSCRIPTION_ID}"]
}
EOF

EXISTING_ROLE=$(az role definition list --name "$CUSTOM_ROLE_NAME" --query "[0].roleName" -o tsv 2>/dev/null || true)
if [ -z "$EXISTING_ROLE" ]; then
  if az role definition create --role-definition "$ROLE_JSON_FILE" >/dev/null 2>&1; then
    echo "✓ Custom role created: $CUSTOM_ROLE_NAME"
    echo "  Waiting for role to propagate (30s)..."
    sleep 30
  else
    echo "⚠ Skipping role create (insufficient permissions — owner must run this once)"
  fi
else
  if az role definition update --role-definition "$ROLE_JSON_FILE" >/dev/null 2>&1; then
    echo "✓ Custom role updated: $CUSTOM_ROLE_NAME"
  else
    echo "⚠ Skipping role update (insufficient permissions — owner must run this once)"
  fi
fi
rm -f "$ROLE_JSON_FILE"

# Assign role to managed identity
az role assignment create \
  --assignee "$IDENTITY_OBJECT_ID" \
  --role "$CUSTOM_ROLE_NAME" \
  --scope "$RG_SCOPE" 2>/dev/null \
  && echo "✓ Role assigned to managed identity" \
  || echo "✓ Role already assigned (skipped)"

# Also assign AKS Cluster Admin role
az role assignment create \
  --assignee "$IDENTITY_OBJECT_ID" \
  --role "Azure Kubernetes Service Cluster Admin Role" \
  --scope "$RG_SCOPE" 2>/dev/null \
  && echo "✓ AKS Cluster Admin role assigned" \
  || echo "✓ AKS Cluster Admin role already assigned (skipped)"

# ── Step 5: Build Pritunl users JSON for cloud-init ───────────────────────
USERS_JSON="[]"
for user_entry in "${PRITUNL_USERS[@]:-}"; do
  name="${user_entry%%:*}"
  email="${user_entry##*:}"
  USERS_JSON=$(echo "$USERS_JSON" | jq --arg n "$name" --arg e "$email" '. += [{"name":$n,"email":$e}]')
done

# ── Step 6: Build GitHub runner URL ───────────────────────────────────────
if [ -n "$GITHUB_REPO" ]; then
  GITHUB_URL="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}"
else
  GITHUB_URL="https://github.com/${GITHUB_ORG}"
fi

# ── Step 7: Generate setup script ─────────────────────────────────────────
# Generated once; used for both new VM (cloud-init) and existing VM (az run-command)
SETUP_SCRIPT=$(mktemp)
cat > "$SETUP_SCRIPT" <<SETUPSCRIPT
#!/bin/bash
set -e
LOG=/var/log/runner-setup.log
exec > >(tee -a \$LOG) 2>&1
echo "=== Setup start \$(date) ==="
VPN_ENABLED="${VPN_ENABLED}"

# Configure Azure DNS so private AKS endpoints (privatelink.*.azmk8s.io) resolve correctly
mkdir -p /etc/systemd/resolved.conf.d
echo -e "[Resolve]\nDNS=168.63.129.16" > /etc/systemd/resolved.conf.d/azure.conf
systemctl restart systemd-resolved

# Base packages (cloud-init may not have run)
apt-get update -qq
apt-get install -y -qq unzip jq curl git openssl ca-certificates gnupg

# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# kubectl
KUBECTL_VER=\$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -sLO "https://dl.k8s.io/release/\${KUBECTL_VER}/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

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
usermod -aG docker azureuser

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
    RESPONSE=\$(curl -s -k -X PUT "https://localhost/auth/session" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"pritunl\",\"password\":\"\${DEFAULT_PASS}\"}")
    echo "Pritunl auth response: \$RESPONSE"
    TOKEN=\$(echo "\$RESPONSE" | jq -r '.token // empty' 2>/dev/null || echo "")
    if [ -n "\$TOKEN" ]; then
      ORG_ID=\$(curl -s -k -X POST "https://localhost/organization" \
        -H "Auth-Token: \$TOKEN" -H "Content-Type: application/json" \
        -d '{"name":"${PRITUNL_ORG_NAME}"}' | jq -r '.id')
      SERVER_ID=\$(curl -s -k -X POST "https://localhost/server" \
        -H "Auth-Token: \$TOKEN" -H "Content-Type: application/json" \
        -d '{"name":"runner-vpn","protocol":"wireguard","port":1194,"network":"${PRITUNL_VPN_NETWORK}","dns_servers":["168.63.129.16"]}' | jq -r '.id')
      curl -s -k -X POST "https://localhost/server/\${SERVER_ID}/route" \
        -H "Auth-Token: \$TOKEN" -H "Content-Type: application/json" \
        -d '{"network":"10.0.0.0/8","comment":"VNet + AKS"}'
      curl -s -k -X PUT "https://localhost/server/\${SERVER_ID}/organization/\${ORG_ID}" \
        -H "Auth-Token: \$TOKEN"
      curl -s -k -X PUT "https://localhost/server/\${SERVER_ID}/operation/start" \
        -H "Auth-Token: \$TOKEN"
      echo '${USERS_JSON}' | jq -c '.[]' | while read user; do
        NAME=\$(echo \$user | jq -r '.name')
        EMAIL=\$(echo \$user | jq -r '.email')
        curl -s -k -X POST "https://localhost/user/\${ORG_ID}" \
          -H "Auth-Token: \$TOKEN" -H "Content-Type: application/json" \
          -d "{\"name\":\"\${NAME}\",\"email\":\"\${EMAIL}\"}"
      done
      echo "Pritunl configured."
    else
      echo "WARNING: Pritunl API auth failed. Check https://\$(curl -s ifconfig.me)"
    fi
  fi
else
  echo "VPN_ENABLED=false - skipping Pritunl."
fi

# GitHub Actions Runner
echo "==> Installing GitHub Actions Runner..."
set +e
RUNNER_VERSION=\$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
mkdir -p /home/azureuser/actions-runner && cd /home/azureuser/actions-runner
curl -sLO "https://github.com/actions/runner/releases/download/v\${RUNNER_VERSION}/actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz" 2>&1 | tee /tmp/runner-download.log
tar xzf "actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz"
rm "actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz"
chown -R azureuser:azureuser /home/azureuser/actions-runner
sudo -u azureuser ./config.sh \
  --url "${GITHUB_URL}" \
  --token "${GITHUB_RUNNER_TOKEN}" \
  --name "\$(hostname)" \
  --labels "self-hosted,azure,linux" \
  --unattended --replace 2>&1 | tee /tmp/runner-config.log
RUNNER_CONFIG_STATUS=\$?
set -e
if [ \$RUNNER_CONFIG_STATUS -ne 0 ]; then
  echo "ERROR: GitHub Actions runner registration failed. Reason:"
  tail -20 /tmp/runner-config.log
else
  ./svc.sh install azureuser && ./svc.sh start
  echo "✓ GitHub Actions runner registered and started."
fi
echo "=== Setup complete \$(date) ==="
echo "SUCCESS" > /tmp/setup-status
SETUPSCRIPT

# ── Step 7b: Wrap setup script in cloud-init for new VM ───────────────────
# Use base64 encoding so { } characters in the bash script don't break YAML parsing.
SETUP_SCRIPT_B64=$(openssl base64 -A -in "$SETUP_SCRIPT")
CLOUD_INIT_FILE=$(mktemp)
cat > "$CLOUD_INIT_FILE" <<CLOUDINIT
#cloud-config

package_update: true
packages:
  - jq
  - curl
  - git
  - unzip
  - openssl

write_files:
  - path: /opt/setup.sh
    permissions: '0755'
    encoding: b64
    content: ${SETUP_SCRIPT_B64}

runcmd:
  - bash /opt/setup.sh
CLOUDINIT

# ── Step 8: Create VM or run setup on existing VM ──────────────────────────
VM_EXISTED="false"
if az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" &>/dev/null; then
  VM_EXISTED="true"
  echo "✓ VM already exists: $VM_NAME — running setup via Azure Run Command (~10 min)..."
  RUN_OUTPUT=$(az vm run-command invoke \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --command-id RunShellScript \
    --scripts @"$SETUP_SCRIPT" \
    --query "value[0].message" -o tsv 2>&1)
  echo "$RUN_OUTPUT"
  VM_IP_CHECK=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --show-details --query publicIps -o tsv)
  SETUP_STATUS=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 azureuser@"$VM_IP_CHECK" 'cat /tmp/setup-status 2>/dev/null || echo UNKNOWN')
  if [ "$SETUP_STATUS" = "SUCCESS" ]; then
    echo "✓ Setup completed successfully on existing VM."
  else
    echo "ERROR: Setup failed or output was truncated. Check full log:"
    echo "  ssh azureuser@${VM_IP_CHECK} 'sudo tail -100 /var/log/runner-setup.log'"
    exit 1
  fi
  rm -f "$SETUP_SCRIPT" "$CLOUD_INIT_FILE"
else
  echo "Creating VM... (this takes ~2 minutes)"
  if [ "$VPN_ENABLED" = "true" ]; then
    PUBLIC_IP_ARGS=(--public-ip-sku Standard)
  else
    PUBLIC_IP_ARGS=(--no-public-ip-address)
  fi

  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --image "$VM_IMAGE" \
    --size "$VM_SIZE" \
    --admin-username "$VM_ADMIN_USER" \
    --generate-ssh-keys \
    --assign-identity "$IDENTITY_ID" \
    --custom-data "$CLOUD_INIT_FILE" \
    --vnet-name "$VNET_NAME" \
    --subnet "$RUNNER_SUBNET_NAME" \
    "${PUBLIC_IP_ARGS[@]}" >/dev/null

  rm -f "$SETUP_SCRIPT" "$CLOUD_INIT_FILE"
  echo "✓ VM created: $VM_NAME"
fi

# ── Open NSG ports (VPN only) ─────────────────────────────────────────────
if [ "$VPN_ENABLED" = "true" ]; then
  # Azure auto-creates NSG named <VM_NAME>NSG
  VM_NSG="${VM_NAME}NSG"

  # Fallback: look up via NIC if default name doesn't exist
  if ! az network nsg show --resource-group "$RESOURCE_GROUP" --name "$VM_NSG" &>/dev/null; then
    NIC_ID=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" \
      --query "networkProfile.networkInterfaces[0].id" -o tsv)
    NSG_ID=$(az network nic show --ids "$NIC_ID" --query "networkSecurityGroup.id" -o tsv 2>/dev/null || true)
    if [ -n "$NSG_ID" ]; then
      VM_NSG=$(basename "$NSG_ID")
    else
      echo "WARNING: Could not find NSG for VM. Add NSG rules manually: UDP 1194, TCP 443"
      VM_NSG=""
    fi
  fi

  if [ -n "$VM_NSG" ]; then
    az network nsg rule create \
      --resource-group "$RESOURCE_GROUP" --nsg-name "$VM_NSG" \
      --name "allow-wireguard" --priority 100 --protocol Udp \
      --destination-port-range 1194 --access Allow 2>/dev/null || true

    az network nsg rule create \
      --resource-group "$RESOURCE_GROUP" --nsg-name "$VM_NSG" \
      --name "allow-pritunl-ui" --priority 110 --protocol Tcp \
      --destination-port-range 443 --access Allow 2>/dev/null || true

    az network nsg rule create \
      --resource-group "$RESOURCE_GROUP" --nsg-name "$VM_NSG" \
      --name "allow-openvpn" --priority 120 --protocol Udp \
      --destination-port-range 12535 --access Allow 2>/dev/null || true

    echo "✓ NSG rules added (UDP 1194, UDP 12535, TCP 443)"
  fi
else
  echo "✓ VPN disabled - no NSG rules added (VM has no public IP; access via Azure Bastion)"
fi

# ── Done ───────────────────────────────────────────────────────────────────
echo "Runner VM setup complete."
echo "VM: $VM_NAME"
if [ "$VPN_ENABLED" = "true" ]; then
  VM_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" \
    --show-details --query publicIps -o tsv)
  echo "Public IP: $VM_IP"
  echo "SSH: ssh azureuser@${VM_IP}"
else
  echo "Public IP: none (private VM, access via Azure Bastion after create_tf_resources)"
fi

if [ "$VM_EXISTED" = "true" ]; then
  echo "Setup complete. Runner and VPN are ready."
else
  echo "cloud-init running in background (~10 min). Check: ssh azureuser@${VM_IP:-<ip>} 'sudo tail -f /var/log/runner-setup.log'"
fi

echo "Runner: https://github.com/${GITHUB_ORG}/${GITHUB_REPO:+${GITHUB_REPO}/}settings/actions/runners"

if [ "$VPN_ENABLED" = "true" ]; then
  PRITUNL_CREDS=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 azureuser@"$VM_IP" 'cat /tmp/pritunl-creds 2>/dev/null || echo ""')
  PRITUNL_PASS=$(echo "$PRITUNL_CREDS" | cut -d: -f2)
  echo "Pritunl VPN: https://${VM_IP}"
  echo "Pritunl username: pritunl"
  if [ -n "$PRITUNL_PASS" ]; then
    echo "Pritunl password: ${PRITUNL_PASS}"
  else
    echo "Pritunl password: ssh azureuser@${VM_IP} 'sudo pritunl default-password'"
  fi
fi
