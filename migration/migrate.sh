#!/usr/bin/env bash
#
# Pre-deploy migration: runs the 6 sub-steps of Phase 4 (DB imports + DB-only fixups).
#
# Phases NOT in this script — run via GitHub Action:
#   Phase 2  infra              → create_tf_backend + backup_configs + create_tf_resources
#   Phase 3  data-tier install  → install_service edbb/learnbb/knowledgebb (kafka, yugabytedb, es, janusgraph)
#   Phase 5  full deploy        → install_helm=true, helm_mode=all
#   Phase 8  validate           → generate_postman_env + migrate_forms
#
# This script only runs the pure helm-driven migration steps:
#   4.1  databases.ysql                 (PostgreSQL  → YSQL)
#   4.2  dbFixups.keycloakCredentials   (rotate creds in YSQL)
#   4.3  databases.ycql                 (Cassandra   → YCQL)
#   4.4  databases.janusgraph           (Neo4j       → JanusGraph)
#   4.5  databases.elasticsearch        (ES snapshot → ES)
#   4.6  dbFixups.createdatBackfill     (backfill column)
#
# PRE-REQUISITES:
#   1. Phase 1 export already done (artifacts in object storage).
#   2. Phases 2 + 3 already done via GitHub Action.
#   3. migration/database/import/values.yaml filled in:
#        - dbFixups.keycloakCredentials.adminPassword + secretSuffix
#        - databases.ycql.targetPrefix matches NEW global.env (e.g. "dv_")
#   4. kubectl context points to NEW cluster.
#
# NEXT after this script:
#   - Trigger Action with install_helm=true, helm_mode=all (= Phase 5).
#   - Wait for keycloak / knowlg-service / lern-service Deployments to become Ready.
#   - Run ./post-migrate.sh.
#
# Usage:
#   ./migration/migrate.sh                                # all 6 sub-steps
#   ./migration/migrate.sh 4.1                            # only YSQL
#   ./migration/migrate.sh 4.3 4.4 4.5                    # resume mid-way
#
# Defaults: NAMESPACE=migration, RELEASE=db-migration, HELM_TIMEOUT=60m

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORT_DIR="$SCRIPT_DIR/database/import"

NAMESPACE="${NAMESPACE:-migration}"
RELEASE="${RELEASE:-db-migration}"
HELM_TIMEOUT="${HELM_TIMEOUT:-60m}"

log() { echo -e "\n\033[1;36m[migrate] $*\033[0m"; }
die() { echo -e "\033[1;31m[migrate ERROR] $*\033[0m" >&2; exit 1; }

[ -d "$IMPORT_DIR" ] || die "IMPORT_DIR not found: $IMPORT_DIR"
command -v helm    >/dev/null 2>&1 || die "helm not found in PATH"
command -v kubectl >/dev/null 2>&1 || die "kubectl not found in PATH"

# Enable exactly ONE pre-deploy block. All others forced false so only the
# requested helm hook fires. Reads import/values.yaml for credentials.
helm_pre() {
  local enable_key="$1"
  helm upgrade --install "$RELEASE" "$IMPORT_DIR" \
    -f "$IMPORT_DIR/values.yaml" \
    -n "$NAMESPACE" --create-namespace \
    --timeout "$HELM_TIMEOUT" --wait \
    --set databases.ysql.enabled=false \
    --set databases.ycql.enabled=false \
    --set databases.janusgraph.enabled=false \
    --set databases.elasticsearch.enabled=false \
    --set dbFixups.keycloakCredentials.enabled=false \
    --set dbFixups.createdatBackfill.enabled=false \
    --set "${enable_key}.enabled=true"
}

step_4_1() { log "4.1  PostgreSQL → YSQL";              helm_pre databases.ysql; }
step_4_2() { log "4.2  Rotate Keycloak credentials";    helm_pre dbFixups.keycloakCredentials; }
step_4_3() { log "4.3  Cassandra → YCQL";               helm_pre databases.ycql; }
step_4_4() { log "4.4  Neo4j → JanusGraph";             helm_pre databases.janusgraph; }
step_4_5() { log "4.5  ES snapshot → Elasticsearch";    helm_pre databases.elasticsearch; }
step_4_6() { log "4.6  createdat backfill";             helm_pre dbFixups.createdatBackfill; }

run_step() {
  case "$1" in
    4.1) step_4_1 ;;
    4.2) step_4_2 ;;
    4.3) step_4_3 ;;
    4.4) step_4_4 ;;
    4.5) step_4_5 ;;
    4.6) step_4_6 ;;
    all)
      step_4_1
      step_4_2
      step_4_3
      step_4_4
      step_4_5
      step_4_6
      ;;
    *) die "unknown step: $1 (allowed: all, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6)" ;;
  esac
}

if [ $# -eq 0 ]; then
  run_step all
else
  for arg in "$@"; do
    run_step "$arg"
  done
fi

log "Phase 4 done."
log "NEXT: trigger GitHub Action with install_helm=true, helm_mode=all (= Phase 5)."
log "Then run ./post-migrate.sh once keycloak / knowlg-service / lern-service are Ready."
