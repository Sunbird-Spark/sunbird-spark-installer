#!/bin/bash
set -euo pipefail

###############################################################
# Azure OIDC Setup — DEPLOY Service Principal
#
# Creates (or reuses) the deploy SP used by GitHub Actions to
# run Helm deployments and kubectl commands against the AKS
# cluster. Assigned the AKS Cluster Admin role.
#
# Output: AZURE_DEPLOY_CLIENT_ID
#
# Prerequisite: the AKS cluster must already exist.
###############################################################

# ── CONFIGURE THESE BEFORE RUNNING ──────────────────────────────────────────
TENANT_ID=""           # Your Azure AD Tenant ID
SUBSCRIPTION_ID=""     # Your Azure Subscription ID
BUILDING_BLOCK=""      # Must match global.building_block in global-values.yaml (e.g. "ed")
ENVIRONMENT=""         # Must match configs/ folder and GitHub Actions environment name (e.g. "testing")
RESOURCE_GROUP=""      # Azure resource group where the AKS cluster lives (e.g. "ed-testing")
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
CLUSTER_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}"
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
CLUSTER_SCOPE="$RG_SCOPE/providers/Microsoft.ContainerService/managedClusters/$CLUSTER_NAME"

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

# ── Login ──────────────────────────────────────────────────
echo "Logging in to Azure..."
az login --tenant $TENANT_ID
az account set --subscription $SUBSCRIPTION_ID
echo "✓ Subscription: $SUBSCRIPTION_ID"

# ── Set up DEPLOY SP ───────────────────────────────────────
echo ""
echo "── Setting up DEPLOY service principal ───────────────"
DEPLOY_APP_NAME="${APP_NAME}-deploy"
DEPLOY_CLIENT_ID=$(create_or_reuse_sp "$DEPLOY_APP_NAME")
DEPLOY_OBJECT_ID=$(az ad sp show --id "$DEPLOY_CLIENT_ID" --query id -o tsv)

add_federated_credential "$DEPLOY_CLIENT_ID" "${GITHUB_ENVIRONMENT}-deploy"
assign_role "$DEPLOY_OBJECT_ID" "Azure Kubernetes Service Cluster Admin Role" "$CLUSTER_SCOPE"
assign_role "$DEPLOY_OBJECT_ID" "Azure Kubernetes Service Cluster User Role"  "$CLUSTER_SCOPE"

echo "✓ Deploy SP ready: $DEPLOY_APP_NAME"

# ── Output ─────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  Add this to GitHub Actions Secrets:"
echo "  Repo → Settings → Environments → $GITHUB_ENVIRONMENT → Secrets"
echo "=============================================="
echo ""
echo "  AZURE_DEPLOY_CLIENT_ID = $DEPLOY_CLIENT_ID"
echo ""
echo "=============================================="
