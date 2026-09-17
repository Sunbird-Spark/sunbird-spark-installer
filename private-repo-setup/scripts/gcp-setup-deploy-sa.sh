#!/bin/bash
set -euo pipefail

###############################################################
# GCP OIDC Setup — DEPLOY Service Account
#
# Creates (or reuses):
#   - Deploy SA scoped to the existing GKE cluster
#   - Cluster-scoped roles (clusterViewer + developer)
#   - Bucket-scoped read on the private bucket
#   - WIF impersonation binding for the GitHub repo
#
# Prerequisite: GKE cluster must already exist (Phase 1 done).
# Reuses the WI Pool + provider created by gcp-setup-infra-sa.sh.
#
# Output: GCP_DEPLOY_SA_EMAIL
###############################################################

# ── CONFIGURE THESE ─────────────────────────────────────────
PROJECT_ID=""          # GCP project ID
BUILDING_BLOCK=""      # matches global.building_block
ENVIRONMENT=""         # matches configs/ folder name
REGION=""              # GKE cluster region (e.g. "asia-south1")
PRIVATE_BUCKET=""      # name of the private bucket holding global-cloud-values.yaml
GITHUB_REPO=""         # "org-name/spark-devops"
GITHUB_ENVIRONMENT=""  # GitHub Actions environment name
# ─────────────────────────────────────────────────────────────

for var in PROJECT_ID BUILDING_BLOCK ENVIRONMENT REGION PRIVATE_BUCKET GITHUB_REPO GITHUB_ENVIRONMENT; do
  if [ -z "${!var}" ]; then
    echo "ERROR: $var not set"; exit 1
  fi
done

POOL_ID="${BUILDING_BLOCK}-${ENVIRONMENT}-pool"
SA_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}-deploy-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
CLUSTER_NAME="${BUILDING_BLOCK}-${ENVIRONMENT}"

gcloud config set project "$PROJECT_ID"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)")

# ── Verify pool exists (created by gcp-setup-infra-sa.sh) ──
if ! gcloud iam workload-identity-pools describe "$POOL_ID" --location=global >/dev/null 2>&1; then
  echo "ERROR: WI Pool '$POOL_ID' not found. Run gcp-setup-infra-sa.sh first."
  exit 1
fi

# ── Verify cluster exists ──────────────────────────────────
if ! gcloud container clusters describe "$CLUSTER_NAME" --region="$REGION" >/dev/null 2>&1; then
  echo "ERROR: GKE cluster '$CLUSTER_NAME' not found in region '$REGION'."
  echo "Run Phase 1 (create_tf_resources) first."
  exit 1
fi

# ── Create deploy SA (idempotent) ──────────────────────────
if ! gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="${BUILDING_BLOCK} ${ENVIRONMENT} Deploy SA"
  echo "Deploy SA created: $SA_EMAIL"
  sleep 10
else
  echo "Deploy SA exists: $SA_EMAIL (reused)"
fi

# ── Bind cluster-scoped roles via IAM condition ────────────
# Limits roles to the single cluster only — cannot mutate other clusters.
CLUSTER_RESOURCE="//container.googleapis.com/projects/${PROJECT_ID}/locations/${REGION}/clusters/${CLUSTER_NAME}"
CONDITION_TITLE="${BUILDING_BLOCK}_${ENVIRONMENT}_cluster_only"
CONDITION_EXPR="resource.name == '${CLUSTER_RESOURCE}'"

for role in roles/container.clusterViewer roles/container.developer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$role" \
    --condition="title=${CONDITION_TITLE},expression=${CONDITION_EXPR}" >/dev/null
  echo "Bound: $role (cluster-scoped via condition)"
done

# ── Bind bucket-scoped read on private bucket ──────────────
gcloud storage buckets add-iam-policy-binding "gs://${PRIVATE_BUCKET}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectViewer" >/dev/null
echo "Bound: roles/storage.objectViewer on gs://${PRIVATE_BUCKET}"

# ── Allow GitHub OIDC to impersonate SA ────────────────────
PRINCIPAL="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${GITHUB_REPO}"

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role=roles/iam.workloadIdentityUser \
  --member="$PRINCIPAL" >/dev/null
echo "WIF impersonation binding added"

# ── Output ─────────────────────────────────────────────────
cat <<EOF

==============================================
  Add this to GitHub Actions Secrets:
  Repo -> Settings -> Environments -> ${GITHUB_ENVIRONMENT} -> Secrets
==============================================

  GCP_DEPLOY_SA_EMAIL = ${SA_EMAIL}

==============================================
EOF
