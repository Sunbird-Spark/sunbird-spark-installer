#!/usr/bin/env bash
#
# Post-deploy migration: runs the 3 sub-steps of Phase 6 (post-migration
# reconciles that require app services running).
#
# Runs ONLY AFTER:
#   1. ./migrate.sh has completed (Phase 4).
#   2. GitHub Action has run install_helm=true, helm_mode=all (= Phase 5).
#   3. keycloak / knowlg-service / lern-service Deployments on the NEW cluster
#      have >= 1 Ready replica. This script verifies that automatically and
#      fails fast if any is not ready.
#
# Steps:
#   6.1  postMigration.keycloakRealmReconcile
#   6.2  postMigration.hierarchyFix
#   6.3  postMigration.userProgressSync
#
# Phase 8 (generate_postman_env + migrate_forms) is NOT in this script —
# run via GitHub Action: generate_postman_env + migrate_forms.
#
# Usage:
#   ./migration/post-migrate.sh           # all 3 sub-steps
#   ./migration/post-migrate.sh 6.1       # only realm reconcile
#   ./migration/post-migrate.sh 6.2 6.3   # resume mid-way
#
# Defaults: NAMESPACE=migration, TARGET_NS=sunbird, RELEASE=db-migration, HELM_TIMEOUT=30m

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT_DIR="$SCRIPT_DIR/database/import"

NAMESPACE="${NAMESPACE:-migration}"
TARGET_NS="${TARGET_NS:-sunbird}"
RELEASE="${RELEASE:-db-migration}"
HELM_TIMEOUT="${HELM_TIMEOUT:-30m}"

log() { echo -e "\n\033[1;36m[post-migrate] $*\033[0m"; }
die() { echo -e "\033[1;31m[post-migrate ERROR] $*\033[0m" >&2; exit 1; }

[ -d "$IMPORT_DIR" ] || die "IMPORT_DIR not found: $IMPORT_DIR"
command -v helm    >/dev/null 2>&1 || die "helm not found in PATH"
command -v kubectl >/dev/null 2>&1 || die "kubectl not found in PATH"

# Verify a Deployment in $TARGET_NS has >= 1 ready replica.
check_deployment_ready() {
  local name="$1"
  local ready
  ready=$(kubectl get deployment -n "$TARGET_NS" "$name" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  if [ -z "${ready:-}" ] || [ "$ready" -lt 1 ]; then
    die "Deployment '$name' in ns '$TARGET_NS' has no ready replicas (got: '$ready'). Phase 5 must complete + services must be healthy before running post-migrate."
  fi
  log "  ✓ $name ready ($ready replica(s))"
}

preflight() {
  log "Pre-flight: checking required services in ns/$TARGET_NS"
  check_deployment_ready keycloak
  check_deployment_ready knowlg-service
  check_deployment_ready lern-service
}

# Enable exactly ONE post-deploy block.
helm_post() {
  local enable_key="$1"
  helm upgrade --install "$RELEASE" "$IMPORT_DIR" \
    -f "$IMPORT_DIR/values.yaml" \
    -n "$NAMESPACE" --create-namespace \
    --timeout "$HELM_TIMEOUT" --wait \
    --set postMigration.keycloakRealmReconcile.enabled=false \
    --set postMigration.hierarchyFix.enabled=false \
    --set postMigration.userProgressSync.enabled=false \
    --set "${enable_key}.enabled=true"
}

step_6_1() { log "6.1  keycloakRealmReconcile";  helm_post postMigration.keycloakRealmReconcile; }
step_6_2() { log "6.2  hierarchyFix";            helm_post postMigration.hierarchyFix; }
step_6_3() { log "6.3  userProgressSync";        helm_post postMigration.userProgressSync; }

run_step() {
  case "$1" in
    6.1) step_6_1 ;;
    6.2) step_6_2 ;;
    6.3) step_6_3 ;;
    all)
      step_6_1
      step_6_2
      step_6_3
      ;;
    *) die "unknown step: $1 (allowed: all, 6.1, 6.2, 6.3)" ;;
  esac
}

preflight

if [ $# -eq 0 ]; then
  run_step all
else
  for arg in "$@"; do
    run_step "$arg"
  done
fi

log "Phase 6 done."
log "NEXT (manual via GitHub Action):"
log "  - Phase 8: trigger Action with generate_postman_env + migrate_forms."
log "  - Phase 7: DNS swap to NEW cluster nginx IP."
