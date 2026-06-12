#!/usr/bin/env bash
#
# End-to-end test of the migration against a local ES7 + OpenSearch pair.
#
#   SNAPSHOT_SRC=/Users/chethan/test/es-backup-08-06-2026 ./run-test.sh
#
# Brings up the compose stack, waits for health, runs the full migration
# (restore -> es7 -> opensearch), then prints a side-by-side doc-count diff
# between ES7 and OpenSearch so you can confirm no data was lost.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../migrate-es-to-opensearch.sh"
SNAPSHOT_SRC="${SNAPSHOT_SRC:-/Users/chethan/test/es-backup-08-06-2026}"
SNAPSHOT_NAME="${SNAPSHOT_NAME:-snapshot_08_06_2026}"

command -v jq >/dev/null || { echo "jq required"; exit 1; }
[ -d "$SNAPSHOT_SRC" ] || { echo "snapshot dir not found: $SNAPSHOT_SRC"; exit 1; }

# prefer the compose v2 plugin, fall back to the standalone docker-compose
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  echo "neither 'docker compose' nor 'docker-compose' found"; exit 1
fi
# -p pins the project so we never adopt/remove containers from other projects
PROJECT=sunbird-es-os-migration-test
dc() { $COMPOSE -p "$PROJECT" -f "$HERE/docker-compose.yml" "$@"; }

echo "### bringing up es7 + opensearch (snapshot: $SNAPSHOT_SRC)"
SNAPSHOT_SRC="$SNAPSHOT_SRC" dc up -d

wait_healthy() { # url
  echo -n "waiting for $1 "
  for _ in $(seq 1 60); do
    if curl -sf "$1/_cluster/health" >/dev/null 2>&1; then echo " up"; return 0; fi
    echo -n "."; sleep 5
  done
  echo " TIMEOUT"; return 1
}
wait_healthy http://localhost:9200   # ES7
wait_healthy http://localhost:9201   # OpenSearch

echo "### running migration (all phases)"
ES_HOST=localhost:9200 \
OS_HOST=localhost:9201 \
SNAPSHOT_NAME="$SNAPSHOT_NAME" \
SNAPSHOT_LOCATION=/usr/share/elasticsearch/snapshots \
REMOTE_ES_HOST=http://es7:9200 \
ES7_FILES_DIR="$HERE/../../elasticsearch/v7.10" \
OS_FILES_DIR="$HERE/../../opensearch/v2.19.5" \
bash "$SCRIPT"

echo
echo "### doc-count diff  (index | es7 | opensearch)   [top-level _count]"
# NOTE: use the _count API on BOTH sides. _cat/indices docs.count includes
# nested Lucene docs (compositesearch/course-batch/userv3 have nested fields),
# which would show false mismatches against OpenSearch top-level counts.
indices=$(curl -s 'localhost:9200/_cat/indices?format=json' | jq -r '.[]|select(.index|startswith(".")|not)|.index' | sort)
mismatch=0
while read -r idx; do
  ec=$(curl -s "localhost:9200/$idx/_count" | jq -r '.count // "MISSING"')
  oc=$(curl -s "localhost:9201/$idx/_count" | jq -r '.count // "MISSING"')
  flag=""; [ "$ec" != "$oc" ] && { flag="  <-- MISMATCH"; mismatch=1; }
  printf "%-28s %8s %8s%s\n" "$idx" "$ec" "$oc" "$flag"
done <<< "$indices"

echo
if [ "$mismatch" = 0 ]; then echo "RESULT: PASS — all counts match, no data lost"; else echo "RESULT: FAIL — see mismatches above"; fi

echo
echo "### compositesearch knn check on OpenSearch"
curl -s 'localhost:9201/compositesearch/_settings' | jq '.compositesearch.settings.index.knn'
curl -s 'localhost:9201/compositesearch/_mappings' | jq '.compositesearch.mappings.properties.chunks.properties.embedding.dimension'

echo
echo "(tear down with:  $COMPOSE -p $PROJECT -f $HERE/docker-compose.yml down -v)"
