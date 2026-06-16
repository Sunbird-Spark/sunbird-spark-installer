# Elasticsearch 6.8.23 → Elasticsearch 7.10.2 → OpenSearch 2.19.5 migration

This migration moves Sunbird search data from the legacy **Elasticsearch
6.8.23** stack onto the new **OpenSearch 2.19.5** stack used by the current
chart.

It is a **three-step** migration on purpose — a direct snapshot restore from
ES 6.8 into OpenSearch 2.19 does **not** work:

| # | Step | Why it is needed |
|---|------|------------------|
| 1 | Restore the ES 6.8 snapshot onto **ES 7.10.2** | We start from a filesystem snapshot taken on the old cluster. |
| 2 | **Reindex** every v6 index in place on ES 7.10 | OpenSearch 2.x refuses any index whose metadata says `created = 6.x` (`"cannot be upgraded … should be re-indexed in 7.x first"`). Reindexing rewrites the index so its metadata becomes 7.x. |
| 3 | Create v2.19.5 indices on OpenSearch and **remote-reindex** the docs | A plain restore would carry the *old* mappings. OpenSearch needs its own definitions (e.g. `compositesearch` requires `index.knn=true` + a `knn_vector` field for semantic search). We pre-create the correct indices, then copy only the documents. |

All steps are **count-verified** and **idempotent**: nothing is deleted until
its replacement exists and the document count matches. On any failure the
temporary/holding index is kept, so data is always recoverable from either the
temp index or the original snapshot.

---

## Which path applies to you?

What matters is the **version your indices were created with**, not the
version of the cluster you currently run. Check it:

```bash
curl -s 'your-es:9200/<index>/_settings' | jq '.[].settings.index.version.created'
# 7100299 -> created on ES 7.10   |   6082399 -> created on ES 6.8
```

| Your indices were created with… | What you need |
|----------------------------------|---------------|
| **Elasticsearch 7.10** | **Only the OpenSearch step.** No reindex needed — see [Already on Elasticsearch 7.10](#already-on-elasticsearch-710) below. |
| **Elasticsearch 6.8** | The full 3-step path (`PHASE=all`): reindex 6.8 → 7.10 first (OpenSearch 2.x rejects v6 indices), then move to OpenSearch. |

> Even on a 7.10 cluster, an index can still carry `created = 6.8` if it was
> originally made on ES 6.8 and only snapshot-restored onto 7.10. Those indices
> need the 6.8 path. When in doubt, check `version.created` as shown above.

---

## Already on Elasticsearch 7.10

Your indices were created on ES 7.10, so OpenSearch 2.x can restore them
directly — **no reindex needed**. The flow is a straight snapshot restore,
followed by a one-time fix of `compositesearch` so semantic search (kNN) works.

**The flow at a glance:**

1. Take a snapshot from Elasticsearch 7.10.
2. Bring Elasticsearch **down** and OpenSearch 2.19.5 **up**.
3. **Clear** any existing data in OpenSearch.
4. **Restore** the snapshot into OpenSearch.
5. Create a new **`compositesearch_v2`** index with the kNN settings + mappings.
6. **Reindex** `compositesearch` → `compositesearch_v2`.
7. **Rename** `compositesearch_v2` back to `compositesearch`.

Steps 5–7 exist because `index.knn` is a **static** setting: a restored
`compositesearch` comes back without it, and you cannot add it to an existing
index — so you rebuild it once. Everything else restores as-is.

---

### Step 1 — snapshot on Elasticsearch 7.10

Set the repo path in `elasticsearch.yml` (then restart), register the repo,
record a baseline, and snapshot:

```bash
# elasticsearch.yml ->  path.repo: ["/usr/share/elasticsearch/snapshots"]

# baseline for later validation
curl -s 'elasticsearch:9200/_cat/indices?v'
curl -s 'elasticsearch:9200/_cat/count?v'

# register repo + snapshot (skip system indices, don't carry cluster state)
curl -X PUT 'elasticsearch:9200/_snapshot/es-backup' -H 'Content-Type: application/json' -d '{
  "type":"fs","settings":{"location":"/usr/share/elasticsearch/snapshots","compress":true}}'

curl -X PUT 'elasticsearch:9200/_snapshot/es-backup/snapshot_1?wait_for_completion=true' \
  -H 'Content-Type: application/json' \
  -d '{"indices":"*,-.*","ignore_unavailable":true,"include_global_state":false}'

# confirm state == SUCCESS
curl -s 'elasticsearch:9200/_snapshot/es-backup/snapshot_1' | jq '.snapshots[0].state'
```

> **Azure Blob** instead of filesystem: install `repository-azure` on both
> clusters, add `azure.client.default.account`/`.key` to the keystore, reload
> secure settings, and register an `azure`-type repo. The snapshot/restore
> calls are otherwise identical.

### Step 2 — Elasticsearch down, OpenSearch up

Stop Elasticsearch so nothing writes during the cutover, and make sure the
OpenSearch 2.19.5 cluster is GREEN:

```bash
curl -s 'opensearch:9200/_cluster/health?v'
# opensearch.yml ->  path.repo: ["/usr/share/opensearch/snapshots"]   (restart after)
```

For a filesystem repo, copy the snapshot dir to the OpenSearch node and
`chown -R opensearch:opensearch /usr/share/opensearch/snapshots`. For Azure,
nothing to copy.

### Step 3 — clear existing data in OpenSearch

A restore cannot overwrite an open index, so remove any non-system indices
first (skips `.`-prefixed system indices):

```bash
for i in $(curl -s 'opensearch:9200/_cat/indices?format=json' \
            | jq -r '.[]|select(.index|startswith(".")|not)|.index'); do
  curl -s -X DELETE "opensearch:9200/$i" >/dev/null && echo "deleted $i"
done
```

### Step 4 — restore the snapshot into OpenSearch

```bash
curl -X PUT 'opensearch:9200/_snapshot/es-backup' -H 'Content-Type: application/json' -d '{
  "type":"fs","settings":{"location":"/usr/share/opensearch/snapshots"}}'

curl -X POST 'opensearch:9200/_snapshot/es-backup/snapshot_1/_restore?wait_for_completion=true' \
  -H 'Content-Type: application/json' \
  -d '{"indices":"*,-.*","ignore_unavailable":true,"include_global_state":false}'

# validate: counts match the Step 1 baseline, no RED indices
curl -s 'opensearch:9200/_cat/indices?v' | grep -i red    # expect nothing
curl -s 'opensearch:9200/_cat/count?v'
```

### Steps 5–7 — rebuild `compositesearch` with kNN

The restored `compositesearch` has no `index.knn`, so the 1536-dim
`knn_vector` writes fail with `vector's dimensions must be <= [1024]`. Rebuild
it once via a `_v2` index, then rename. Docs are preserved and count-verified.

```bash
OS=opensearch:9200
DIR=../opensearch/v2.19.5      # ships compositesearch.json (knn=true) + mapping

orig=$(curl -s "$OS/compositesearch/_count" | jq .count)

# 5. create compositesearch_v2 with kNN settings + mappings
curl -X PUT "$OS/compositesearch_v2"          -H 'Content-Type: application/json' --data-binary "@$DIR/indices/compositesearch.json"
curl -X PUT "$OS/compositesearch_v2/_mapping" -H 'Content-Type: application/json' --data-binary "@$DIR/mappings/compositesearch-mapping.json"

# 6. reindex compositesearch -> compositesearch_v2  (+ verify)
curl -X POST "$OS/_reindex?wait_for_completion=true&refresh=true" -H 'Content-Type: application/json' \
  -d '{"source":{"index":"compositesearch"},"dest":{"index":"compositesearch_v2"}}'
test "$(curl -s "$OS/compositesearch_v2/_count" | jq .count)" = "$orig" || { echo "COUNT MISMATCH — stop"; }

# 7. rename: drop old, copy _v2 back into a fresh compositesearch, drop _v2
curl -X DELETE "$OS/compositesearch"
curl -X PUT  "$OS/compositesearch"          -H 'Content-Type: application/json' --data-binary "@$DIR/indices/compositesearch.json"
curl -X PUT  "$OS/compositesearch/_mapping" -H 'Content-Type: application/json' --data-binary "@$DIR/mappings/compositesearch-mapping.json"
curl -X POST "$OS/_reindex?wait_for_completion=true&refresh=true" -H 'Content-Type: application/json' \
  -d '{"source":{"index":"compositesearch_v2"},"dest":{"index":"compositesearch"}}'
test "$(curl -s "$OS/compositesearch/_count" | jq .count)" = "$orig" \
  && curl -X DELETE "$OS/compositesearch_v2" \
  && echo "DONE: knn=$(curl -s "$OS/compositesearch/_settings" | jq -r '.compositesearch.settings.index.knn'), docs=$orig"
```

> OpenSearch has no true "rename" — step 7 is delete + recreate + reindex. If
> you'd rather not rebuild a second time, you can instead point an **alias**
> `compositesearch` → `compositesearch_v2` and skip step 7; most readers prefer
> the real index name, which is why the rename is shown.

Only decommission Elasticsearch after OpenSearch is validated and backed up.

---

## Files

```
files/
├── elasticsearch/v7.10/          # ES7-compatible index defs (generated from
│   ├── indices/                  #   the v2.19.5 set, kNN stripped out)
│   ├── mappings/
│   └── pipelines/
├── opensearch/v2.19.5/           # OpenSearch index defs (source of truth)
│   ├── indices/                  #   compositesearch has index.knn=true +
│   ├── mappings/                 #   chunks.embedding knn_vector(1536, BYTE)
│   └── pipelines/
└── migration/
    ├── migrate-es-to-opensearch.sh   # the one migration script
    ├── README.md                     # this file
    └── test/
        ├── docker-compose.yml        # ES 7.10.2 + OpenSearch 2.19.5
        └── run-test.sh               # end-to-end local test + count diff
```

> The `elasticsearch/v7.10` set is **derived** from `opensearch/v2.19.5` by
> removing OpenSearch-only features (`index.knn` and any `knn_vector` fields),
> which ES 7.10 does not understand. Everything else (analyzers, n-gram
> filter, `total_fields` limit, text/keyword fields) is identical, so ES7 and
> OpenSearch stay consistent. Regenerate with:
> ```bash
> for f in files/opensearch/v2.19.5/indices/*.json; do
>   jq 'if .settings.index.knn then del(.settings.index.knn) else . end' "$f" \
>     > "files/elasticsearch/v7.10/indices/$(basename "$f")"; done
> for f in files/opensearch/v2.19.5/mappings/*.json; do
>   jq 'del(.. | objects | select(.type? == "knn_vector"))' "$f" \
>     > "files/elasticsearch/v7.10/mappings/$(basename "$f")"; done
> cp files/opensearch/v2.19.5/pipelines/*.json files/elasticsearch/v7.10/pipelines/
> ```

---

## Running the script standalone

The script needs only `curl` and `jq`.

```bash
PHASE=all \
ES_HOST=es7-host:9200 \
OS_HOST=opensearch-host:9200 \
SNAPSHOT_REPO=es-backup \
SNAPSHOT_NAME=snapshot_08_06_2026 \
SNAPSHOT_LOCATION=/usr/share/elasticsearch/snapshots \
REMOTE_ES_HOST=http://es7-host:9200 \
ES7_FILES_DIR=../elasticsearch/v7.10 \
OS_FILES_DIR=../opensearch/v2.19.5 \
./migrate-es-to-opensearch.sh
```

### Phases

| `PHASE` | Action |
|---------|--------|
| `restore` | Register the fs snapshot repo on ES7 and restore it (`*,-.*`, `include_global_state:false`). Verifies the snapshot is `SUCCESS` first. |
| `es7` | Reindex every **v6-created** index in place so its metadata becomes v7. v7+ indices are skipped. Uses the curated `elasticsearch/v7.10` files when present, otherwise derives the mapping from the source (copies analyzers, raises `max_ngram_diff`, removes the obsolete `standard` token filter). |
| `opensearch` | Create each index on OpenSearch from `opensearch/v2.19.5` files, then **remote-reindex** documents from ES7. Applies ingest pipelines. |
| `all` *(default)* | `restore` → `es7` → `opensearch`. |

### Key environment variables

| Var | Default | Notes |
|-----|---------|-------|
| `ES_HOST` / `OS_HOST` | `localhost:9200` / `localhost:9201` | host:port |
| `ES_SCHEME` / `OS_SCHEME` | `http` | set `https` if TLS |
| `ES_USER`/`ES_PASS`, `OS_USER`/`OS_PASS` | — | optional basic auth |
| `SNAPSHOT_REPO` | `es-backup` | fs repo name on ES7 |
| `SNAPSHOT_NAME` | newest | auto-detects latest if unset |
| `SNAPSHOT_LOCATION` | `/usr/share/elasticsearch/snapshots` | must equal an ES7 `path.repo` entry |
| `REMOTE_ES_HOST` | `http://$ES_HOST` | how **OpenSearch** reaches ES7; must be in `reindex.remote.whitelist` |
| `INCLUDE` | — | restrict to specific indices (space/comma list) |

> **Remote reindex prerequisite:** OpenSearch must allow remote reindex from
> ES7. Add to `opensearch.yml` (static, needs restart):
> ```yaml
> reindex.remote.whitelist: "es7-host:9200"
> ```

---

## Running manually (Elasticsearch 6.8 source)

This is a **standalone script** — there is no Helm Job. Run it by hand from a
machine that can reach both the ES 7.10 cluster and the OpenSearch 2.19.5
cluster, with `curl` and `jq` installed.

**Prerequisites**

1. Stand up an **Elasticsearch 7.10.2** cluster and restore your ES 6.8
   snapshot onto it — or let the script do the restore (`PHASE=restore`/`all`)
   if the snapshot repo is mounted at `SNAPSHOT_LOCATION`.
2. Stand up the **OpenSearch 2.19.5** cluster.
3. Whitelist remote reindex on OpenSearch — add to `opensearch.yml` (static,
   needs a restart):
   ```yaml
   reindex.remote.whitelist: "es7-host:9200"
   ```

**Run all three phases:**

```bash
cd helmcharts/learnbb/files/migration

PHASE=all \
ES_HOST=es7-host:9200 \
OS_HOST=opensearch-host:9200 \
SNAPSHOT_REPO=es-backup \
SNAPSHOT_NAME=snapshot_08_06_2026 \
SNAPSHOT_LOCATION=/usr/share/elasticsearch/snapshots \
REMOTE_ES_HOST=http://es7-host:9200 \
ES7_FILES_DIR=../elasticsearch/v7.10 \
OS_FILES_DIR=../opensearch/v2.19.5 \
./migrate-es-to-opensearch.sh
```

Or run the phases one at a time (`PHASE=restore`, then `es7`, then
`opensearch`) to checkpoint between steps. The script is **idempotent** and
**count-verified**, so it is safe to re-run.

After it finishes, spot-check counts and the kNN fix:

```bash
# top-level doc counts must match between ES7 and OpenSearch
curl -s 'es7-host:9200/<index>/_count'
curl -s 'opensearch-host:9200/<index>/_count'

# compositesearch must have knn enabled on OpenSearch
curl -s 'opensearch-host:9200/compositesearch/_settings' | jq '.compositesearch.settings.index.knn'
```

> The existing `opensearch-migration` provisioning Job in this chart only
> **creates empty** OpenSearch indices for fresh installs. It does **not** move
> data. This migration script is the separate, manual path for carrying
> existing ES 6.8 data forward.

---

## Local end-to-end test (testing only — not part of the deployment)

> Everything under `files/migration/test/` exists **only to test the script**.
> It is not used by any deployment and can be ignored in production. It brings
> up throwaway ES 7.10.2 + OpenSearch 2.19.5 containers, runs the full
> migration against an example snapshot, and verifies no data was lost.

Requires Docker. From `files/migration/test/`:

```bash
SNAPSHOT_SRC=/path/to/es-backup-08-06-2026 ./run-test.sh
```

`run-test.sh`:
1. starts `es7` (`:9200`) and `os` (`:9201`) via `docker-compose.yml`,
2. waits for both to be healthy,
3. runs `migrate-es-to-opensearch.sh` `PHASE=all`,
4. prints a side-by-side **doc-count diff** (ES7 vs OpenSearch) and a
   `PASS/FAIL` verdict,
5. checks `compositesearch` has `index.knn=true` and `chunks.embedding.dimension`.

Tear down (project-scoped — never use `--remove-orphans` here, it can remove
unrelated containers): `docker compose -p sunbird-es-os-migration-test -f docker-compose.yml down -v`.

The example snapshot `es-backup-08-06-2026` was taken on ES 7.10.2 and contains
indices created on **ES 6.8.23** (`version.created = 6082399`) — exercising the
full 6.8 → 7.10 → OpenSearch path.

---

## What the script guarantees

- **No data loss:** every reindex is followed by a `_count` comparison against
  the source; the original/holding index is only deleted after the replacement
  count matches.
- **Idempotent:** re-running skips indices that are already v7 (es7 phase) or
  already present with matching counts (opensearch phase).
- **System indices untouched:** anything matching `^\.` is skipped.
- **Auditable:** every run writes `migration-<timestamp>.log` and, if anything
  fails, `migration-failed-<timestamp>.txt` listing the affected indices.
