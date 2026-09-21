#!/bin/bash
set -euo pipefail

###############################################################
# GCP OIDC Setup — INFRA Service Account
#
# Creates (or reuses):
#   - Workload Identity Pool + GitHub OIDC provider (one-time)
#   - Custom role `installer_role` (no SA key perms)
#   - Infra SA bound to custom role at project scope
#   - WIF impersonation binding for the GitHub repo
#
# Outputs: GCP_INFRA_SA_EMAIL, GCP_WORKLOAD_IDENTITY_PROVIDER,
#          GCP_PROJECT_ID, GCP_PROJECT_NUMBER
###############################################################

# ── CONFIGURE THESE ─────────────────────────────────────────
PROJECT_ID=""          # GCP project ID
BUILDING_BLOCK=""      # matches global.building_block
ENVIRONMENT=""         # matches configs/ folder name
GITHUB_REPO=""         # "org-name/spark-devops"
GITHUB_ENVIRONMENT=""  # GitHub Actions environment name
# ─────────────────────────────────────────────────────────────

for var in PROJECT_ID BUILDING_BLOCK ENVIRONMENT GITHUB_REPO GITHUB_ENVIRONMENT; do
  if [ -z "${!var}" ]; then
    echo "ERROR: $var not set"; exit 1
  fi
done

POOL_ID="${BUILDING_BLOCK}-${ENVIRONMENT}-pool"
PROVIDER_ID="github-provider"
SA_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-infra-sa"
ROLE_ID="${BUILDING_BLOCK}_${ENVIRONMENT}_installer_role"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud config set project "$PROJECT_ID"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

# ── Enable required APIs ───────────────────────────────────
echo "Enabling APIs..."
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  cloudresourcemanager.googleapis.com \
  container.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com \
  serviceusage.googleapis.com

# ── Create Workload Identity Pool (idempotent) ─────────────
if ! gcloud iam workload-identity-pools describe "$POOL_ID" --location=global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$POOL_ID" \
    --location=global \
    --display-name="${BUILDING_BLOCK} ${ENVIRONMENT} Pool"
  echo "Pool created: $POOL_ID"
else
  echo "Pool exists: $POOL_ID (reused)"
fi

# ── Create OIDC Provider for GitHub (idempotent) ───────────
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_ID" \
     --location=global --workload-identity-pool="$POOL_ID" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
    --location=global \
    --workload-identity-pool="$POOL_ID" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.environment=assertion.environment,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository == '${GITHUB_REPO}'"
  echo "OIDC provider created: $PROVIDER_ID"
else
  echo "OIDC provider exists: $PROVIDER_ID (reused)"
fi

WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}"

# ── Create custom installer role (idempotent) ──────────────
ROLE_FILE=$(mktemp)
cat > "$ROLE_FILE" <<EOF
title: "${BUILDING_BLOCK} ${ENVIRONMENT} Installer Role"
description: "Least-priv role for sunbird-spark installer infra SA. No SA key creation."
stage: GA
includedPermissions:
  - compute.networks.create
  - compute.networks.delete
  - compute.networks.get
  - compute.networks.list
  - compute.networks.update
  - compute.networks.updatePolicy
  - compute.subnetworks.create
  - compute.subnetworks.delete
  - compute.subnetworks.get
  - compute.subnetworks.list
  - compute.subnetworks.update
  - compute.subnetworks.use
  - compute.subnetworks.useExternalIp
  - compute.routers.create
  - compute.routers.delete
  - compute.routers.get
  - compute.routers.list
  - compute.routers.update
  - compute.routers.use
  - compute.firewalls.create
  - compute.firewalls.delete
  - compute.firewalls.get
  - compute.firewalls.list
  - compute.firewalls.update
  - compute.zones.get
  - compute.zones.list
  - compute.regions.get
  - compute.regions.list
  - compute.machineTypes.get
  - compute.machineTypes.list
  - compute.diskTypes.get
  - compute.diskTypes.list
  - compute.instances.get
  - compute.instances.list
  - container.clusters.create
  - container.clusters.delete
  - container.clusters.get
  - container.clusters.list
  - container.clusters.update
  - container.clusters.getCredentials
  - container.operations.get
  - container.operations.list
  - container.nodes.create
  - container.nodes.delete
  - container.nodes.get
  - container.nodes.list
  - container.nodes.update
  - storage.buckets.create
  - storage.buckets.delete
  - storage.buckets.get
  - storage.buckets.list
  - storage.buckets.update
  - storage.buckets.getIamPolicy
  - storage.buckets.setIamPolicy
  - storage.objects.create
  - storage.objects.delete
  - storage.objects.get
  - storage.objects.list
  - storage.objects.update
  - iam.serviceAccounts.create
  - iam.serviceAccounts.delete
  - iam.serviceAccounts.get
  - iam.serviceAccounts.list
  - iam.serviceAccounts.update
  - iam.serviceAccounts.actAs
  - iam.serviceAccounts.getIamPolicy
  - iam.serviceAccounts.setIamPolicy
  - iam.roles.create
  - iam.roles.delete
  - iam.roles.get
  - iam.roles.list
  - iam.roles.update
  - resourcemanager.projects.get
  - resourcemanager.projects.getIamPolicy
  - resourcemanager.projects.setIamPolicy
  - serviceusage.services.enable
  - serviceusage.services.get
  - serviceusage.services.list
EOF

if gcloud iam roles describe "$ROLE_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam roles update "$ROLE_ID" --project="$PROJECT_ID" --file="$ROLE_FILE" >/dev/null
  echo "Custom role updated: $ROLE_ID"
else
  gcloud iam roles create "$ROLE_ID" --project="$PROJECT_ID" --file="$ROLE_FILE" >/dev/null
  echo "Custom role created: $ROLE_ID"
fi
rm -f "$ROLE_FILE"

# ── Create infra SA (idempotent) ───────────────────────────
if ! gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="${BUILDING_BLOCK} ${ENVIRONMENT} Infra SA"
  echo "Infra SA created: $SA_EMAIL"
  sleep 10
else
  echo "Infra SA exists: $SA_EMAIL (reused)"
fi

# ── Bind custom role to SA at project scope ────────────────
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="projects/${PROJECT_ID}/roles/${ROLE_ID}" \
  --condition=None >/dev/null
echo "Custom role bound to SA"

# ── Allow GitHub OIDC to impersonate SA ────────────────────
PRINCIPAL="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}"

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role=roles/iam.workloadIdentityUser \
  --member="$PRINCIPAL" >/dev/null
echo "WIF impersonation binding added"

# ── Output ─────────────────────────────────────────────────
cat <<EOF

==============================================
  Add these to GitHub Actions Secrets:
  Repo -> Settings -> Environments -> ${GITHUB_ENVIRONMENT} -> Secrets
==============================================

  GCP_PROJECT_ID                 = ${PROJECT_ID}
  GCP_PROJECT_NUMBER             = ${PROJECT_NUMBER}
  GCP_INFRA_SA_EMAIL             = ${SA_EMAIL}
  GCP_WORKLOAD_IDENTITY_PROVIDER = ${WIF_PROVIDER}

  Also add:
  ANSIBLE_VAULT_PASSWORD = <vault password>

==============================================
EOF
