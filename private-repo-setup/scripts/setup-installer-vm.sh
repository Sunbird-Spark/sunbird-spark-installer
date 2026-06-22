#!/bin/bash
set -euo pipefail

###############################################################
# Azure VM Setup — Sunbird Spark Installer VM
#
# This script:
# 1. Creates a VM with UserAssigned managed identity
# 2. Creates a custom least-privilege role and assigns it
# 3. Installs Pritunl VPN + WireGuard via cloud-init
# 4. Registers GitHub Actions self-hosted runner via cloud-init
#
# Run ONCE per environment from owner's laptop.
# After this, all infra + deployments run via GitHub Actions.
###############################################################

# ── CONFIGURE THESE BEFORE RUNNING ──────────────────────────────────────────
TENANT_ID=""              # Azure AD Tenant ID (Azure Portal → Azure Active Directory → Overview)
SUBSCRIPTION_ID=""        # Azure Subscription ID (Azure Portal → Subscriptions)
BUILDING_BLOCK=""         # Must match global.building_block in global-values.yaml (e.g. "ed")
ENVIRONMENT=""            # Must match configs/ folder name (e.g. "dev", "prod")
RESOURCE_GROUP=""         # Azure resource group (e.g. "ed-dev")
LOCATION=""               # Azure region (e.g. "Central India")
GITHUB_ORG=""             # GitHub org name (e.g. "Sunbird-Spark")
GITHUB_REPO=""            # GitHub repo name for repo-level runner, or leave empty for org-level
GITHUB_RUNNER_TOKEN=""    # GitHub → Settings → Actions → Runners → New runner → copy token
PRITUNL_VPN_NETWORK=""    # VPN client IP pool (e.g. "172.16.0.0/24")
PRITUNL_ORG_NAME=""       # Pritunl org name (e.g. "sunbird-spark")
# PRITUNL_USERS: space-separated "name:email" pairs
# e.g. PRITUNL_USERS=("divya:divya@example.com" "dev2:dev2@example.com")
PRITUNL_USERS=()
# ─────────────────────────────────────────────────────────────────────────────

# ── Validate inputs ────────────────────────────────────────────────────────
for var in TENANT_ID SUBSCRIPTION_ID BUILDING_BLOCK ENVIRONMENT RESOURCE_GROUP LOCATION GITHUB_ORG GITHUB_RUNNER_TOKEN PRITUNL_VPN_NETWORK PRITUNL_ORG_NAME; do
  if [ -z "${!var}" ]; then
    echo "❌ ERROR: $var is not set. Edit the variables at the top of this script."
    exit 1
  fi
done

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
az identity create \
  --name "$IDENTITY_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" >/dev/null
IDENTITY_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
IDENTITY_OBJECT_ID=$(az identity show --name "$IDENTITY_NAME" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)
echo "✓ Managed identity created: $IDENTITY_NAME ($IDENTITY_OBJECT_ID)"

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
  az role definition create --role-definition "$ROLE_JSON_FILE" >/dev/null
  echo "✓ Custom role created: $CUSTOM_ROLE_NAME"
  echo "  Waiting for role to propagate (30s)..."
  sleep 30
else
  az role definition update --role-definition "$ROLE_JSON_FILE" >/dev/null
  echo "✓ Custom role updated: $CUSTOM_ROLE_NAME"
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

# ── Step 7: Create cloud-init script ──────────────────────────────────────
CLOUD_INIT_FILE=$(mktemp)
cat > "$CLOUD_INIT_FILE" <<CLOUDINIT
#cloud-config

package_update: true
packages:
  - wireguard
  - jq
  - curl
  - git
  - unzip
  - openssl

write_files:
  - path: /opt/setup.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -e
      LOG=/var/log/runner-setup.log
      exec > >(tee -a \$LOG) 2>&1
      echo "=== Setup start \$(date) ==="

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
      unzip -q tofu_\${TOFU_VERSION}_linux_amd64.zip -d /usr/local/bin/ && rm tofu_\${TOFU_VERSION}_linux_amd64.zip

      # Terragrunt
      curl -sLo /usr/local/bin/terragrunt "https://github.com/gruntwork-io/terragrunt/releases/download/v0.77.5/terragrunt_linux_amd64"
      chmod +x /usr/local/bin/terragrunt

      # yq
      curl -sLo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v4.44.1/yq_linux_amd64"
      chmod +x /usr/local/bin/yq

      # rclone
      curl https://rclone.org/install.sh | bash

      # Docker
      curl -fsSL https://get.docker.com | bash
      usermod -aG docker azureuser

      # Pritunl
      echo "deb https://repo.pritunl.com/stable/apt jammy main" > /etc/apt/sources.list.d/pritunl.list
      apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv 7568D9BB55FF9E5287D586017AE645C0CF8E292A
      apt-get update -qq && apt-get install -y pritunl mongodb
      systemctl enable mongod pritunl && systemctl start mongod && sleep 5 && systemctl start pritunl && sleep 15

      # Configure Pritunl
      DEFAULT_PASS=\$(pritunl default-password | grep "Password:" | awk '{print \$2}')
      RESPONSE=\$(curl -s -k -X PUT "https://localhost/auth/session" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"pritunl\",\"password\":\"\${DEFAULT_PASS}\"}")
      TOKEN=\$(echo \$RESPONSE | jq -r '.token // empty')

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
        echo "WARNING: Pritunl API auth failed. Manual setup needed at https://\$(curl -s ifconfig.me)"
      fi

      # GitHub Actions Runner
      RUNNER_VERSION=\$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
      mkdir -p /home/azureuser/actions-runner && cd /home/azureuser/actions-runner
      curl -sLO "https://github.com/actions/runner/releases/download/v\${RUNNER_VERSION}/actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz"
      tar xzf "actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz"
      rm "actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz"
      chown -R azureuser:azureuser /home/azureuser/actions-runner

      sudo -u azureuser ./config.sh \
        --url "${GITHUB_URL}" \
        --token "${GITHUB_RUNNER_TOKEN}" \
        --name "\$(hostname)" \
        --labels "self-hosted,azure,linux" \
        --unattended --replace

      ./svc.sh install azureuser && ./svc.sh start
      echo "=== Setup complete \$(date) ==="

runcmd:
  - bash /opt/setup.sh
CLOUDINIT

# ── Step 8: Create VM with managed identity + cloud-init ──────────────────
echo "Creating VM... (this takes ~2 minutes)"
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
  --public-ip-sku Standard >/dev/null

rm -f "$CLOUD_INIT_FILE"
echo "✓ VM created: $VM_NAME"

# ── Open NSG ports ─────────────────────────────────────────────────────────
VM_NSG=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" \
  --query "networkProfile.networkInterfaces[0].id" -o tsv | xargs az network nic show --ids \
  --query "networkSecurityGroup.id" -o tsv | xargs basename)

az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" --nsg-name "$VM_NSG" \
  --name "allow-wireguard" --priority 100 --protocol Udp \
  --destination-port-range 1194 --access Allow 2>/dev/null || true

az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" --nsg-name "$VM_NSG" \
  --name "allow-pritunl-ui" --priority 110 --protocol Tcp \
  --destination-port-range 443 --access Allow 2>/dev/null || true

echo "✓ NSG rules added (UDP 1194, TCP 443)"

# ── Done ───────────────────────────────────────────────────────────────────
VM_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" \
  --show-details --query publicIps -o tsv)

echo ""
echo "=========================================="
echo "  Runner VM Setup Complete"
echo "=========================================="
echo "  VM Name       : $VM_NAME"
echo "  Public IP     : $VM_IP"
echo "  SSH           : ssh azureuser@${VM_IP} (key in ~/.ssh/)"
echo ""
echo "  cloud-init running in background (~5 min):"
echo "  - Installs: Pritunl, WireGuard, kubectl, helm, tofu, az CLI"
echo "  - Configures VPN server + users"
echo "  - Registers GitHub Actions runner"
echo ""
echo "  Check runner: https://github.com/${GITHUB_ORG} → Settings → Actions → Runners"
echo "  VPN portal:   https://${VM_IP}  (ready after ~5 min)"
echo ""
echo "  Next: Trigger GitHub Actions workflow to create AKS + deploy"
echo "=========================================="
