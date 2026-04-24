#!/bin/bash
set -euo pipefail

###############################################################
# Azure VM Setup — Sunbird Spark Installer VM
#
# This script:
# 1. Creates a VM with SystemAssigned managed identity
# 2. Creates a custom least-privilege role and assigns it to
#    the VM's managed identity
#
# Purpose: the VM is used to run the Sunbird Spark installer
# manually via SSH. The managed identity gives it the
# permissions needed to run OpenTofu (create AKS, networking,
# storage, workload-identity...) without storing any credentials.
#
# Scope: role is assigned at RG scope — VM can only act
#        inside $RESOURCE_GROUP.
###############################################################

# ── CONFIGURE THESE BEFORE RUNNING ──────────────────────────────────────────
TENANT_ID=""        # Your Azure AD Tenant ID (Azure Portal → Azure Active Directory → Overview)
SUBSCRIPTION_ID=""  # Your Azure Subscription ID (Azure Portal → Subscriptions)
BUILDING_BLOCK=""   # Short resource prefix — must match global.building_block in global-values.yaml (e.g. "myorg")
ENVIRONMENT=""      # Environment name — must match your configs/ folder name (e.g. "prod")
RESOURCE_GROUP=""   # Azure resource group to create the VM in (e.g. "myorg-prod")
LOCATION=""         # Azure region (e.g. "Central India", "East US", "Southeast Asia")
# ─────────────────────────────────────────────────────────────────────────────

# ── Validate inputs ────────────────────────────────────────
for var in TENANT_ID SUBSCRIPTION_ID BUILDING_BLOCK ENVIRONMENT RESOURCE_GROUP LOCATION; do
  if [ -z "${!var}" ]; then
    echo "❌ ERROR: $var is not set. Please edit the variables at the top of this script before running."
    exit 1
  fi
done

# VM config
VM_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-installer-vm"
VM_SIZE="Standard_B2s"
VM_IMAGE="Ubuntu2204"
VM_ADMIN_USER="azureuser"
SSH_KEY_PATH="$HOME/.ssh/${VM_NAME}"

# Custom role config
CUSTOM_ROLE_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-installer-role"

# ── Step 1: Login ──────────────────────────────────────────
az login --tenant $TENANT_ID
az account set --subscription $SUBSCRIPTION_ID
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
echo "✓ Subscription: $SUBSCRIPTION_ID"

# ── Step 2: Generate SSH Key ───────────────────────────────
mkdir -p "$HOME/.ssh"
ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "${VM_NAME}"
chmod 400 "${SSH_KEY_PATH}"
echo "✓ SSH private key saved: ${SSH_KEY_PATH}"
echo "✓ SSH public  key saved: ${SSH_KEY_PATH}.pub"

# ── Step 3: Create or Reuse Resource Group ─────────────────
RG_EXISTS=$(az group exists --name $RESOURCE_GROUP -o tsv)

if [ "$RG_EXISTS" == "true" ]; then
  echo "✓ Resource group already exists, reusing: $RESOURCE_GROUP"
else
  az group create \
    --name $RESOURCE_GROUP \
    --location "$LOCATION"
  echo "✓ Resource group created: $RESOURCE_GROUP"
fi

# ── Step 4: Create VM with SystemAssigned Managed Identity ─
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --image $VM_IMAGE \
  --size $VM_SIZE \
  --admin-username $VM_ADMIN_USER \
  --ssh-key-values "${SSH_KEY_PATH}.pub" \
  --assign-identity "[system]"
echo "✓ VM created: $VM_NAME"

# ── Step 5: Get VM Managed Identity Object ID ──────────────
VM_OBJECT_ID=$(az vm identity show \
  --name $VM_NAME \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv)
echo "✓ VM Managed Identity: $VM_OBJECT_ID"

echo "Waiting for VM identity to propagate..."
sleep 15

# ── Step 6: Create Least-Privilege Custom Role ─────────────
ROLE_JSON_FILE=$(mktemp)
cat > "$ROLE_JSON_FILE" <<EOF
{
  "Name": "${CUSTOM_ROLE_NAME}",
  "IsCustom": true,
  "Description": "Least-privilege role for Sunbird-Spark installer VM. Lets OpenTofu manage AKS, networking, storage, managed identity, and RBAC inside the target resource group.",
  "Actions": [
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
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete"
  ],
  "NotActions": [],
  "NotDataActions": [],
  "AssignableScopes": [
    "/subscriptions/${SUBSCRIPTION_ID}"
  ]
}
EOF

EXISTING_ROLE=$(az role definition list --name "$CUSTOM_ROLE_NAME" --query "[0].roleName" -o tsv)
if [ -z "$EXISTING_ROLE" ]; then
  az role definition create --role-definition "$ROLE_JSON_FILE" >/dev/null
  echo "✓ Custom role created: $CUSTOM_ROLE_NAME"
  echo "Waiting for role definition to propagate..."
  sleep 30
else
  az role definition update --role-definition "$ROLE_JSON_FILE" >/dev/null
  echo "✓ Custom role updated: $CUSTOM_ROLE_NAME"
fi
rm -f "$ROLE_JSON_FILE"

# ── Step 7: Assign Custom Role to VM Managed Identity ──────
az role assignment create \
  --assignee $VM_OBJECT_ID \
  --role "$CUSTOM_ROLE_NAME" \
  --scope $RG_SCOPE \
  2>/dev/null && echo "✓ Role: $CUSTOM_ROLE_NAME → VM identity" \
  || echo "✓ Role: $CUSTOM_ROLE_NAME already assigned (skipped)"

# ── Done ───────────────────────────────────────────────────
VM_IP=$(az vm show \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --show-details \
  --query publicIps -o tsv)

echo ""
echo "=========================================="
echo "  VM Ready"
echo "=========================================="
echo "  VM Name       : $VM_NAME"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Public IP     : $VM_IP"
echo "  SSH           : ssh -i ${SSH_KEY_PATH} ${VM_ADMIN_USER}@${VM_IP}"
echo "=========================================="
echo "Next: SSH into the VM and follow the manual deployment steps"
echo "in private-repo-setup/README.md → 'Alternative: Manual Deployment via Azure VM'"
echo "=========================================="
