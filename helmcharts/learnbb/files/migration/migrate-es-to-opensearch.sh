#!/usr/bin/env bash
#
# ============================================================================
# Sunbird ES 6.8.23 -> ES 7.10.2 -> OpenSearch 2.19.5 migration
# ============================================================================
#
# Single, idempotent, count-verified migration for clusters upgrading from
# Sunbird "spark" release 1.0.0 (Elasticsearch 6.8.23) to the OpenSearch
# 2.19.5 stack.
#
# Why three steps instead of a direct snapshot restore?
#   * OpenSearch 2.x refuses to restore any index whose metadata says it was
#     created on Elasticsearch 6.x ("cannot be upgraded ... should be
#     re-indexed in 7.x first"). The fix is to reindex on ES 7.10 so the
#     index metadata becomes 7.x, THEN move to OpenSearch.
#   * A plain snapshot restore into OpenSearch also carries the OLD mappings,
#     which lack OpenSearch-only features (e.g. compositesearch needs
#     index.knn=true + a knn_vector field for semantic search). So we
#     pre-create the OpenSearch indices from the v2.19.5 definitions and then
#     copy only the documents in via remote reindex.
#
# Phases (set PHASE):
#   restore     register the filesystem snapshot repo on ES7 and restore it
#   es7         reindex every v6-created index in place so it becomes v7
#   opensearch  create the v2.19.5 indices on OpenSearch and remote-reindex
#   all         restore -> es7 -> opensearch   (default)
#
# Nothing is deleted until its replacement has been created AND the document
# count verified. On any failure the holding/temp index is kept so data is
# always recoverable from either the temp index or the original snapshot.
#
# ----------------------------------------------------------------------------
# Configuration (environment variables)
# ----------------------------------------------------------------------------
#   PHASE                restore | es7 | opensearch | all      (default: all)
#
#   ES_HOST              ES 7.10 host:port      (default: localhost:9200)
#   OS_HOST              OpenSearch 2.19 host:port (default: localhost:9201)
#   ES_SCHEME / OS_SCHEME  http | https         (default: http)
#   ES_USER/ES_PASS, OS_USER/OS_PASS  optional basic-auth creds
#
#   SNAPSHOT_REPO        snapshot repo name on ES7 (default: es-backup)
#   SNAPSHOT_NAME        snapshot to restore (default: auto-detect newest)
#   SNAPSHOT_LOCATION    path.repo location registered on ES7
#                        (default: /usr/share/elasticsearch/snapshots)
#
#   ES7_FILES_DIR        dir with indices/ mappings/ pipelines/ for ES7
#   OS_FILES_DIR         dir with indices/ mappings/ pipelines/ for OpenSearch
#   REMOTE_ES_HOST       how OpenSearch reaches ES7 for remote reindex
#                        (default: http://$ES_HOST). Must be whitelisted on OS
#                        via reindex.remote.whitelist in opensearch.yml.
#
#   INCLUDE              space/comma list to restrict to specific indices
#   SYSTEM_PREFIX_SKIP   regex of index names to always skip (default: ^\.)
# ============================================================================

set -o pipefail

# --------------------------- configuration ---------------------------------
PHASE="${PHASE:-all}"

ES_SCHEME="${ES_SCHEME:-http}"
OS_SCHEME="${OS_SCHEME:-http}"
ES_HOST="${ES_HOST:-localhost:9200}"
OS_HOST="${OS_HOST:-localhost:9201}"

SNAPSHOT_REPO="${SNAPSHOT_REPO:-es-backup}"
SNAPSHOT_NAME="${SNAPSHOT_NAME:-}"
SNAPSHOT_LOCATION="${SNAPSHOT_LOCATION:-/usr/share/elasticsearch/snapshots}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ES7_FILES_DIR="${ES7_FILES_DIR:-$SCRIPT_DIR/../elasticsearch/v7.10}"
OS_FILES_DIR="${OS_FILES_DIR:-$SCRIPT_DIR/../opensearch/v2.19.5}"
REMOTE_ES_HOST="${REMOTE_ES_HOST:-$ES_SCHEME://$ES_HOST}"

INCLUDE="${INCLUDE:-}"
SYSTEM_PREFIX_SKIP="${SYSTEM_PREFIX_SKIP:-^\.}"

TS="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo run)"
LOG_FILE="${LOG_FILE:-migration-$TS.log}"
FAILED_FILE="${FAILED_FILE:-migration-failed-$TS.txt}"

# --------------------------- helpers ---------------------------------------
log()  { echo "$(date '+%H:%M:%S' 2>/dev/null) | $*" | tee -a "$LOG_FILE"; }
die()  { log "FATAL: $*"; exit 1; }
fail() { log "ERROR: $*"; echo "$1" >> "$FAILED_FILE"; }

es()   { curl -s ${ES_USER:+-u "$ES_USER:$ES_PASS"} "$ES_SCHEME://$ES_HOST$1" "${@:2}"; }
os()   { curl -s ${OS_USER:+-u "$OS_USER:$OS_PASS"} "$OS_SCHEME://$OS_HOST$1" "${@:2}"; }

es_count() { es "/$1/_count" | jq -r '.count // "null"'; }
os_count() { os "/$1/_count" | jq -r '.count // "null"'; }

acked() { jq -e '.acknowledged == true' >/dev/null 2>&1; }

require() {
  command -v curl >/dev/null 2>&1 || die "curl not installed"
  command -v jq   >/dev/null 2>&1 || die "jq not installed"
}

# list non-system indices on a cluster ("es" or "os")
list_indices() {
  local who="$1" raw
  if [ "$who" = os ]; then raw=$(os "/_cat/indices?format=json"); else raw=$(es "/_cat/indices?format=json"); fi
  echo "$raw" | jq -r '.[].index' 2>/dev/null \
    | grep -vE "$SYSTEM_PREFIX_SKIP" \
    | grep -v -- '-tmp7-' \
    | { if [ -n "$INCLUDE" ]; then grep -xE "$(echo "$INCLUDE" | tr ', ' '|' | sed 's/|$//')"; else cat; fi; } \
    | sort
}

# index major version on ES7 cluster (created_version)
es_major() {
  local v; v=$(es "/$1/_settings" | jq -r ".\"$1\".settings.index.version.created // empty")
  [ -z "$v" ] && { echo 0; return; }
  echo $(( v / 1000000 ))
}

# Build an ES7 create-body for an index, copying its own settings+mappings
# with the v6 -> v7 fixups. Used for indices that have no curated v7 file
# (e.g. kp_audit_log_*). Prints JSON to stdout, or nothing on failure.
derive_es7_body() {
  local src="$1" settings mappings
  settings=$(es "/$src/_settings" | jq "
      .\"$src\".settings.index
      | {number_of_shards, number_of_replicas, analysis}
      | with_entries(select(.value != null))
      | . + {max_ngram_diff: \"50\", max_shingle_diff: \"10\"}
      | if .analysis.analyzer then
          .analysis.analyzer |= with_entries(
            .value.filter |= (if type==\"array\" then map(select(. != \"standard\"))
                              elif . == \"standard\" then \"lowercase\" else . end))
        else . end")
  mappings=$(es "/$src/_mapping" | jq ".\"$src\".mappings")
  [ -z "$settings" ] || [ "$settings" = null ] && return 1
  [ -z "$mappings" ] || [ "$mappings" = null ] && return 1
  jq -n --argjson s "$settings" --argjson m "$mappings" '{settings:{index:$s}, mappings:$m}'
}

# Create an index on ES7 from curated files if present, else a derived body.
#   create_es7_index <target> <defname> [livesrc]
#     defname  name used to look up curated files (the original index name)
#     livesrc  index to READ from when deriving (defaults to defname). On the
#              recreate step the original is already deleted, so the caller
#              passes the temp index as livesrc.
create_es7_index() {
  local target="$1" defname="$2" livesrc="${3:-$2}"
  local idxfile="$ES7_FILES_DIR/indices/$defname.json"
  local mapfile="$ES7_FILES_DIR/mappings/$defname-mapping.json"
  local r
  if [ -f "$idxfile" ]; then
    r=$(es "/$target" -X PUT -H 'Content-Type: application/json' --data-binary "@$idxfile")
    echo "$r" | acked || { echo "$r" | jq . | tee -a "$LOG_FILE"; return 1; }
    if [ -f "$mapfile" ]; then
      r=$(es "/$target/_mapping" -X PUT -H 'Content-Type: application/json' --data-binary "@$mapfile")
      echo "$r" | acked || { echo "$r" | jq . | tee -a "$LOG_FILE"; return 1; }
    fi
  else
    local body; body=$(derive_es7_body "$livesrc") || return 1
    r=$(es "/$target" -X PUT -H 'Content-Type: application/json' -d "$body")
    echo "$r" | acked || { echo "$r" | jq . | tee -a "$LOG_FILE"; return 1; }
  fi
  return 0
}

es_reindex() { # src dest -> 0 if no failures
  local r f
  r=$(es "/_reindex?wait_for_completion=true&refresh=true" -X POST -H 'Content-Type: application/json' \
        -d "{\"source\":{\"index\":\"$1\"},\"dest\":{\"index\":\"$2\"}}")
  f=$(echo "$r" | jq -r '.failures | length' 2>/dev/null)
  [ "$f" = 0 ] && return 0
  echo "$r" | jq '.failures[0:3]' 2>/dev/null | tee -a "$LOG_FILE"; return 1
}

# ============================================================================
# PHASE: restore  — register fs repo + restore snapshot on ES7
# ============================================================================
phase_restore() {
  log "=== PHASE restore : repo=$SNAPSHOT_REPO location=$SNAPSHOT_LOCATION ==="

  # register (idempotent)
  local r
  r=$(es "/_snapshot/$SNAPSHOT_REPO" -X PUT -H 'Content-Type: application/json' \
        -d "{\"type\":\"fs\",\"settings\":{\"location\":\"$SNAPSHOT_LOCATION\",\"compress\":true}}")
  echo "$r" | acked || { echo "$r" | jq . | tee -a "$LOG_FILE"; die "could not register repo (is path.repo set to $SNAPSHOT_LOCATION ?)"; }
  log "repo registered"

  # pick snapshot
  local snap="$SNAPSHOT_NAME"
  if [ -z "$snap" ]; then
    snap=$(es "/_snapshot/$SNAPSHOT_REPO/_all" | jq -r '.snapshots | sort_by(.start_time_in_millis) | last | .snapshot')
    [ -z "$snap" ] || [ "$snap" = null ] && die "no snapshots found in repo $SNAPSHOT_REPO"
  fi
  log "restoring snapshot: $snap"

  # verify snapshot is healthy before doing anything
  local state failed
  state=$(es "/_snapshot/$SNAPSHOT_REPO/$snap" | jq -r '.snapshots[0].state')
  failed=$(es "/_snapshot/$SNAPSHOT_REPO/$snap" | jq -r '.snapshots[0].shards.failed')
  log "snapshot state=$state failed_shards=$failed"
  [ "$state" = SUCCESS ] || die "snapshot $snap not SUCCESS (state=$state)"

  # restore everything except system indices; don't clobber cluster state
  r=$(es "/_snapshot/$SNAPSHOT_REPO/$snap/_restore?wait_for_completion=true" -X POST \
        -H 'Content-Type: application/json' \
        -d '{"indices":"*,-.*","include_global_state":false}')
  if echo "$r" | jq -e '.snapshot.shards.failed == 0' >/dev/null 2>&1; then
    log "restore OK: $(echo "$r" | jq -r '.snapshot.shards.successful') shards"
  else
    echo "$r" | jq . | tee -a "$LOG_FILE"
    die "restore failed (existing indices? delete non-system indices first, or set INCLUDE)"
  fi
}

# ============================================================================
# PHASE: es7  — reindex every v6 index in place so metadata becomes v7
# ============================================================================
phase_es7() {
  log "=== PHASE es7 : reindex v6 -> v7 on $ES_HOST ==="
  local ok=0 skip=0 errs=0 idx tmp orig tc fc mj

  for idx in $(list_indices es); do
    log "--- $idx"
    mj=$(es_major "$idx")
    if [ "$mj" -ge 7 ]; then log "  skip: already v$mj"; ((skip++)); continue; fi

    orig=$(es_count "$idx")
    [ "$orig" = null ] && { fail "$idx"; ((errs++)); log "  ERROR: no count"; continue; }
    log "  v$mj, docs=$orig"

    tmp="${idx}-tmp7-$TS"
    es "/$tmp" -X DELETE >/dev/null 2>&1   # clear any stale temp

    # 1. temp index with v7 definition (curated file or derived)
    create_es7_index "$tmp" "$idx" || { fail "$idx"; ((errs++)); log "  ERROR: create temp"; continue; }

    # 2. reindex into temp + verify
    es_reindex "$idx" "$tmp" || { fail "$idx"; ((errs++)); es "/$tmp" -X DELETE >/dev/null 2>&1; log "  ERROR: reindex to temp"; continue; }
    tc=$(es_count "$tmp")
    [ "$tc" = "$orig" ] || { fail "$idx"; ((errs++)); es "/$tmp" -X DELETE >/dev/null 2>&1; log "  ERROR: temp count $tc != $orig"; continue; }

    # 3. replace original
    es "/$idx" -X DELETE | acked || { fail "$idx"; ((errs++)); log "  ERROR: delete src (data safe in $tmp)"; continue; }
    sleep 1
    # recreate from curated file by name, deriving from the temp index (the
    # original is gone) when no curated file exists.
    create_es7_index "$idx" "$idx" "$tmp" || { fail "$idx"; ((errs++)); log "  ERROR: recreate (data safe in $tmp)"; continue; }
    es_reindex "$tmp" "$idx" || { fail "$idx"; ((errs++)); log "  ERROR: reindex back (data safe in $tmp)"; continue; }

    # 4. verify + cleanup
    fc=$(es_count "$idx")
    if [ "$fc" = "$orig" ]; then
      es "/$tmp" -X DELETE >/dev/null 2>&1
      log "  OK: $idx now v$(es_major "$idx"), docs=$fc"; ((ok++))
    else
      fail "$idx"; ((errs++)); log "  ERROR: final count $fc != $orig ($tmp kept)"
    fi
  done

  log "es7 summary: ok=$ok skipped=$skip errors=$errs"
  return $(( errs > 0 ? 1 : 0 ))
}

# ============================================================================
# PHASE: opensearch — create v2.19.5 indices on OS and remote-reindex from ES7
# ============================================================================
phase_opensearch() {
  log "=== PHASE opensearch : create indices + remote reindex -> $OS_HOST ==="
  log "remote source as seen by OpenSearch: $REMOTE_ES_HOST"

  # confirm OS can remote-reindex (whitelist)
  local wl
  wl=$(os "/_cluster/settings?include_defaults=true&flat_settings=true" | jq -r '."defaults"."reindex.remote.whitelist" // ."persistent"."reindex.remote.whitelist" // ""')
  log "OpenSearch reindex.remote.whitelist = ${wl:-<empty>}"

  local ok=0 errs=0 idx orig dest_created body pipefile

  for idx in $(list_indices es); do
    log "--- $idx"
    orig=$(es_count "$idx")
    [ "$orig" = null ] && { fail "$idx"; ((errs++)); log "  ERROR: no source count"; continue; }

    # 1. create OS index from curated v2.19.5 files (or auto-create on reindex)
    if os "/$idx" -o /dev/null -w '%{http_code}' | grep -q 200; then
      log "  OS index exists, reusing"
    else
      local idxfile="$OS_FILES_DIR/indices/$idx.json"
      local mapfile="$OS_FILES_DIR/mappings/$idx-mapping.json"
      if [ -f "$idxfile" ]; then
        os "/$idx" -X PUT -H 'Content-Type: application/json' --data-binary "@$idxfile" | acked \
          || { fail "$idx"; ((errs++)); log "  ERROR: create OS index"; continue; }
        [ -f "$mapfile" ] && os "/$idx/_mapping" -X PUT -H 'Content-Type: application/json' --data-binary "@$mapfile" >/dev/null
        log "  created OS index from v2.19.5 files"
      else
        log "  no curated OS file; reindex will auto-create"
      fi
    fi

    # 2. empty source: nothing to copy. Ensure the index simply exists
    #    (a 0-doc remote reindex auto-creates nothing), then it's done.
    if [ "$orig" = 0 ]; then
      if ! os "/$idx" -o /dev/null -w '%{http_code}' | grep -q 200; then
        os "/$idx" -X PUT -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1
      fi
      local dc0; dc0=$(os_count "$idx")
      if [ "$dc0" = 0 ]; then log "  OK: $idx -> OpenSearch, docs=0 (empty)"; ((ok++)); else fail "$idx"; ((errs++)); log "  ERROR: empty index not created (count=$dc0)"; fi
      continue
    fi

    # 3. remote reindex ES7 -> OS
    body=$(jq -n --arg host "$REMOTE_ES_HOST" --arg idx "$idx" \
      '{source:{remote:{host:$host}, index:$idx, size:1000}, dest:{index:$idx}}')
    local r f
    r=$(os "/_reindex?wait_for_completion=true&refresh=true" -X POST -H 'Content-Type: application/json' -d "$body")
    f=$(echo "$r" | jq -r '.failures | length' 2>/dev/null)
    if [ "$f" != 0 ] || [ -z "$f" ]; then
      echo "$r" | jq '.failures[0:3] // .' 2>/dev/null | tee -a "$LOG_FILE"
      fail "$idx"; ((errs++)); log "  ERROR: remote reindex"; continue
    fi

    # 4. verify counts
    local dc; dc=$(os_count "$idx")
    if [ "$dc" = "$orig" ]; then
      log "  OK: $idx -> OpenSearch, docs=$dc"; ((ok++))
    else
      fail "$idx"; ((errs++)); log "  ERROR: OS count $dc != source $orig"
    fi
  done

  # 4. ingest pipelines (from curated OS files)
  if [ -d "$OS_FILES_DIR/pipelines" ]; then
    for pf in "$OS_FILES_DIR/pipelines/"*.json; do
      [ -e "$pf" ] || continue
      local pname; pname=$(basename "$pf" .json)
      os "/_ingest/pipeline/$pname" -X PUT -H 'Content-Type: application/json' --data-binary "@$pf" >/dev/null \
        && log "pipeline applied: $pname"
    done
  fi

  log "opensearch summary: ok=$ok errors=$errs"
  return $(( errs > 0 ? 1 : 0 ))
}

# ============================================================================
main() {
  require
  log "###### migration start : PHASE=$PHASE ######"
  log "ES7=$ES_SCHEME://$ES_HOST  OS=$OS_SCHEME://$OS_HOST"
  log "ES7_FILES_DIR=$ES7_FILES_DIR"
  log "OS_FILES_DIR=$OS_FILES_DIR"

  local rc=0
  case "$PHASE" in
    restore)     phase_restore ;;
    es7)         phase_es7 || rc=1 ;;
    opensearch)  phase_opensearch || rc=1 ;;
    all)         phase_restore; phase_es7 || rc=1; phase_opensearch || rc=1 ;;
    *)           die "unknown PHASE: $PHASE (use restore|es7|opensearch|all)" ;;
  esac

  log "###### migration end : rc=$rc ######"
  if [ -s "$FAILED_FILE" ]; then
    log "FAILED indices (see $FAILED_FILE):"; sort -u "$FAILED_FILE" | tee -a "$LOG_FILE"
  fi
  log "log: $LOG_FILE"
  exit $rc
}

main "$@"
