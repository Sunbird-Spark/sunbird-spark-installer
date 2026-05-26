#!/usr/bin/env bash
#
# Phase 1 export script: runs the 4 sub-steps of the database-export chart
# inside the OLD Sunbird ED 8.1.0 cluster. Produces tarballs in object storage
# that the NEW cluster's import chart (migrate.sh) will consume.
#
# Steps:
#   1.1  databases.postgresql      → <bucket>/postgresql/*.sql.gz
#   1.2  databases.cassandra       → <bucket>/cassandra/<keyspace>.tar.gz
#   1.3  databases.neo4j           → <bucket>/neo4j/neo4j_export.tar.gz
#   1.4  databases.elasticsearch   → <bucket>/cluster-1/snapshots/...
#
# PRE-REQUISITES (before running):
#   1. kubectl context points to OLD ED 8.1.0 cluster.
#   2. migration/database/export/values.yaml filled in:
#        - Source DB endpoints + credentials
#        - Object storage destination (azure storageAccount+accessKey,
#          gcp bucket+serviceAccountKey, or aws s3Bucket+keys+region)
#   3. Target bucket / containers exist and are writable by the export jobs.
#
# After this script completes, the migration moves to the NEW cluster:
#   - Run Phases 2 + 3 via GitHub Action (infra + data-tier install).
#   - Run ./migrate.sh (Phase 4 imports).
#   - Run Phase 5 via GitHub Action (full deploy).
#   - Run ./post-migrate.sh (Phase 6 reconciles).
#   - Phase 7 (DNS swap) + Phase 8 (forms + postman) — see DB-migration.md.
#
# Usage:
#   ./migration/export.sh                       # all 4 sub-steps
#   ./migration/export.sh 1.1                   # only postgresql
#   ./migration/export.sh 1.2 1.3               # resume mid-way
#
# Defaults: NAMESPACE=migration, RELEASE=db-export, HELM_TIMEOUT=60m

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DIR="$SCRIPT_DIR/database/export"

NAMESPACE="${NAMESPACE:-migration}"
RELEASE="${RELEASE:-db-export}"
HELM_TIMEOUT="${HELM_TIMEOUT:-60m}"

log() { echo -e "\n\033[1;36m[export] $*\033[0m"; }
die() { echo -e "\033[1;31m[export ERROR] $*\033[0m" >&2; exit 1; }

[ -d "$EXPORT_DIR" ] || die "EXPORT_DIR not found: $EXPORT_DIR"
command -v helm    >/dev/null 2>&1 || die "helm not found in PATH"
command -v kubectl >/dev/null 2>&1 || die "kubectl not found in PATH"

# Enable exactly ONE source DB at a time. All other databases.* flags forced
# false so only the requested helm hook fires. Reads export/values.yaml for
# credentials + storage destination.
helm_export() {
  local enable_key="$1"
  helm upgrade --install "$RELEASE" "$EXPORT_DIR" \
    -f "$EXPORT_DIR/values.yaml" \
    -n "$NAMESPACE" --create-namespace \
    --timeout "$HELM_TIMEOUT" --wait \
    --set databases.postgresql.enabled=false \
    --set databases.cassandra.enabled=false \
    --set databases.neo4j.enabled=false \
    --set databases.elasticsearch.enabled=false \
    --set "${enable_key}.enabled=true"
}

step_1_1() { log "1.1  PostgreSQL → object storage";   helm_export databases.postgresql; }
step_1_2() { log "1.2  Cassandra → object storage";    helm_export databases.cassandra; }
step_1_3() { log "1.3  Neo4j → object storage";        helm_export databases.neo4j; }
step_1_4() { log "1.4  Elasticsearch snapshot → object storage"; helm_export databases.elasticsearch; }

run_step() {
  case "$1" in
    1.1) step_1_1 ;;
    1.2) step_1_2 ;;
    1.3) step_1_3 ;;
    1.4) step_1_4 ;;
    all)
      step_1_1
      step_1_2
      step_1_3
      step_1_4
      ;;
    *) die "unknown step: $1 (allowed: all, 1.1, 1.2, 1.3, 1.4)" ;;
  esac
}

if [ $# -eq 0 ]; then
  run_step all
else
  for arg in "$@"; do
    run_step "$arg"
  done
fi

log "Phase 1 export done."
log "Verify artifacts in object storage:"
log "  <bucket>/postgresql/*.sql.gz"
log "  <bucket>/cassandra/<keyspace>.tar.gz"
log "  <bucket>/neo4j/neo4j_export.tar.gz"
log "  <bucket>/cluster-1/snapshots/..."
log ""
log "NEXT: switch kubectl context to NEW cluster, then proceed with Phase 2 (GitHub Action)."
