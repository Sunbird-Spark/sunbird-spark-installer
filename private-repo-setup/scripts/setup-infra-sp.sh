#!/bin/bash
set -euo pipefail

###############################################################
# Azure OIDC Setup — INFRA Service Principal
#
# Creates (or reuses) the infra SP used by GitHub Actions to
# run OpenTofu: provisions AKS, VNet, storage, workload
# identity, and the OpenTofu state backend resource group.
#
# Output: AZURE_INFRA_CLIENT_ID
###############################################################

# ── CONFIGURE THESE BEFORE RUNNING ──────────────────────────────────────────
TENANT_ID=""           # Your Azure AD Tenant ID
SUBSCRIPTION_ID=""     # Your Azure Subscription ID
BUILDING_BLOCK=""      # Must match global.building_block in global-values.yaml (e.g. "ed")
ENVIRONMENT=""         # Must match configs/ folder and GitHub Actions environment name (e.g. "testing")
RESOURCE_GROUP=""      # Azure resource group where infra will be created (e.g. "ed-testing")
GITHUB_REPO=""         # Your private devops repo as "org/repo" (e.g. "Sunbird-Spark/spark-devops-test")
GITHUB_ENVIRONMENT=""  # GitHub Actions environment name — must match ENVIRONMENT above
# ─────────────────────────────────────────────────────────────────────────────

# ── Validate inputs ────────────────────────────────────────
for var in TENANT_ID SUBSCRIPTION_ID BUILDING_BLOCK ENVIRONMENT RESOURCE_GROUP GITHUB_REPO GITHUB_ENVIRONMENT; do
  if [ -z "${!var}" ]; then
    echo "❌ ERROR: $var is not set. Please edit the variables at the top of this script before running."
    exit 1
  fi
done

APP_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-github"
CUSTOM_ROLE_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-installer-role"
SUBSCRIPTION_SCOPE="/subscriptions/$SUBSCRIPTION_ID"

# ── Helper: create or reuse an app + SP ───────────────────
create_or_reuse_sp() {
  local name=$1

  local existing_id
  existing_id=$(az ad app list --show-mine --filter "displayName eq '$name'" --query "[0].appId" -o tsv 2>/dev/null || echo "")

  if [ -n "$existing_id" ]; then
    echo "✓ App already exists, reusing: $name ($existing_id)" >&2
    echo "$existing_id"
    return
  fi

  local client_id
  client_id=$(az ad app create --display-name "$name" --query appId -o tsv)
  echo "✓ App created: $name ($client_id)" >&2

  local sp_exists
  sp_exists=$(az ad sp show --id "$client_id" --query id -o tsv 2>/dev/null || echo "")
  if [ -z "$sp_exists" ]; then
    az ad sp create --id "$client_id" >/dev/null
    echo "✓ Service principal created" >&2
    sleep 15
  fi

  echo "$client_id"
}

# ── Helper: add federated credential if not already present ─
add_federated_credential() {
  local client_id=$1
  local cred_name=$2

  local subject="repo:${GITHUB_REPO}:environment:${GITHUB_ENVIRONMENT}"
  local exists
  exists=$(az ad app federated-credential list --id "$client_id" \
    --query "[?subject=='$subject'].name" -o tsv 2>/dev/null || echo "")

  if [ -n "$exists" ]; then
    echo "✓ Federated credential already exists (subject matches), skipping: $cred_name"
    return
  fi

  az ad app federated-credential create --id "$client_id" --parameters "{
    \"name\": \"${cred_name}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GITHUB_REPO}:environment:${GITHUB_ENVIRONMENT}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" >/dev/null
  echo "✓ Federated credential created: $cred_name"
}

# ── Helper: assign role if not already assigned ────────────
assign_role() {
  local assignee=$1
  local role=$2
  local scope=$3

  az role assignment create \
    --assignee "$assignee" \
    --role "$role" \
    --scope "$scope" \
    2>/dev/null && echo "✓ Role assigned: $role" \
    || echo "✓ Role already assigned (skipped): $role"
}

# ── Helper: create or update the custom least-privilege role ─
ensure_custom_role() {
  local role_json_file
  role_json_file=$(mktemp)
  cat > "$role_json_file" <<EOF
{
  "Name": "${CUSTOM_ROLE_NAME}",
  "IsCustom": true,
  "Description": "Least-privilege role for Sunbird-Spark installer. Lets OpenTofu manage AKS, networking, storage, managed identity, and RBAC inside the target resource group.",
  "Actions": [
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/write",
    "Microsoft.Resources/subscriptions/resourceGroups/delete",
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
  "AssignableScopes": [
    "/subscriptions/${SUBSCRIPTION_ID}"
  ]
}
EOF

  local existing
  existing=$(az role definition list --name "$CUSTOM_ROLE_NAME" --query "[0].roleName" -o tsv)
  if [ -z "$existing" ]; then
    az role definition create --role-definition "$role_json_file" >/dev/null
    echo "✓ Custom role created: $CUSTOM_ROLE_NAME"
    echo "Waiting for role definition to propagate..."
    sleep 30
  else
    az role definition update --role-definition "$role_json_file" >/dev/null
    echo "✓ Custom role updated: $CUSTOM_ROLE_NAME"
  fi
  rm -f "$role_json_file"
}

# ── Login ──────────────────────────────────────────────────
echo "Logging in to Azure..."
az login --tenant $TENANT_ID
az account set --subscription $SUBSCRIPTION_ID
echo "✓ Subscription: $SUBSCRIPTION_ID"

# ── Set up INFRA SP ────────────────────────────────────────
echo ""
echo "── Setting up INFRA service principal ────────────────"
ensure_custom_role

INFRA_APP_NAME="${APP_NAME}-infra"
INFRA_CLIENT_ID=$(create_or_reuse_sp "$INFRA_APP_NAME")
INFRA_OBJECT_ID=$(az ad sp show --id "$INFRA_CLIENT_ID" --query id -o tsv)

add_federated_credential "$INFRA_CLIENT_ID" "${GITHUB_ENVIRONMENT}-infra"
assign_role "$INFRA_OBJECT_ID" "$CUSTOM_ROLE_NAME" "$SUBSCRIPTION_SCOPE"

echo "✓ Infra SP ready: $INFRA_APP_NAME"

# ── Output ─────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  Add these to GitHub Actions Secrets:"
echo "  Repo → Settings → Environments → $GITHUB_ENVIRONMENT → Secrets"
echo "=============================================="
echo ""
echo "  AZURE_INFRA_CLIENT_ID = $INFRA_CLIENT_ID"
echo "  AZURE_TENANT_ID       = $TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
echo ""
echo "  Also add:"
echo "  ANSIBLE_VAULT_PASSWORD = <the password you used to encrypt global-values.yaml>"
echo ""
echo "=============================================="
