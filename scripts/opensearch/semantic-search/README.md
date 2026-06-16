# Semantic Search - Bulk Enrich Script

Bulk enrich script that fetches all Content & Collection identifiers from the search service, batches them, and triggers the enrich API to generate semantic embeddings.

## Overview

The enrich API processes content metadata and emits `BE_JOB_REQUEST` Kafka events that trigger downstream enrichment jobs. This script automates the bulk triggering for all Content and Collection items.

**Flow:**
1. Paginate search service `/v3/search` to fetch all Content + Collection identifiers
2. Batch identifiers (respecting API limits)
3. POST to `/v3/enrich` for each batch
4. Track successes and failures

## Prerequisites

- Search service running and accessible
- Enrich API available (typically same service)
- `jq` installed for JSON parsing
- `curl` for HTTP requests

## Usage

### Basic Usage

```bash
chmod +x enrich-all-contents.sh
./enrich-all-contents.sh
```

Defaults to:
- Search API: `http://localhost:9000/v3/search`
- Enrich API: `http://localhost:9000/v3/enrich`
- Batch size: 100 identifiers per request
- Page size: 200 results per search API call

### Custom Configuration

Use environment variables to override defaults:

```bash
# Custom search/enrich endpoints
SEARCH_API=http://prod-search.example.com:9000/v3/search \
ENRICH_API=http://prod-search.example.com:9000/v3/enrich \
./enrich-all-contents.sh

# Custom batch size (smaller for memory-constrained environments)
BATCH_SIZE=50 ./enrich-all-contents.sh

# Custom page size for search service (larger = fewer API calls)
PAGE_SIZE=500 ./enrich-all-contents.sh
```

### Example: Port-Forwarded Service

If using port-forward:

```bash
kubectl port-forward svc/search-service 9000:9000 &
./enrich-all-contents.sh
```

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SEARCH_API` | `http://localhost:9000/v3/search` | Search service endpoint |
| `ENRICH_API` | `http://localhost:9000/v3/enrich` | Enrich API endpoint |
| `BATCH_SIZE` | `100` | Identifiers per enrich request (respect API limit) |
| `PAGE_SIZE` | `200` | Results per search API call (balance between memory/latency) |

## Output

Script generates two log files:

- `enrich-all-TIMESTAMP.log` — Full execution log with per-batch results
- `enrich-failed-TIMESTAMP.txt` — List of identifier that failed (one per line)

Example log:

```
[Wed Jun 10 12:48:22 IST 2026] Starting bulk enrich job...
[Wed Jun 10 12:48:22 IST 2026] Fetching identifiers from http://localhost:9000/v3/search...
[Wed Jun 10 12:48:23 IST 2026] Fetched 200 IDs (total so far: 200)
[Wed Jun 10 12:48:23 IST 2026] Fetched 200 IDs (total so far: 400)
...
[Wed Jun 10 12:48:30 IST 2026] Batch 1: sending 100 IDs to http://localhost:9000/v3/enrich...
[Wed Jun 10 12:48:31 IST 2026] Batch 1: 100 succeeded
...
[Wed Jun 10 12:48:45 IST 2026] ===== ENRICH JOB COMPLETE =====
Total processed: 522
Succeeded: 520
Failed: 2
Batches: 6
Log: enrich-all-20260610_124822.log
Failed IDs: enrich-failed-20260610_124822.txt
```

## API Request Format

### Search Service Query

```json
{
  "request": {
    "filters": {
      "objectType": ["Content", "Collection"]
    },
    "limit": 200,
    "offset": 0
  }
}
```

Response structure:
```json
{
  "result": {
    "count": 522,
    "content": [
      {
        "identifier": "do_123456789",
        "objectType": "Content",
        ...
      }
    ]
  }
}
```

### Enrich API Request

```json
{
  "request": {
    "identifiers": ["do_123456789", "do_987654321", ...]
  }
}
```

Response:
```json
{
  "result": {
    "count": 100,
    "identifiers": ["do_123456789", ...],
    "failed": []
  }
}
```

## Architecture

Script integrates with the Knowledge Platform's semantic search pipeline:

```
enrich-all-contents.sh
    ↓
Search Service (/v3/search)
    ↓
OpenSearch (fetch identifiers)
    ↓
Enrich API (/v3/enrich)
    ↓
Kafka: BE_JOB_REQUEST topic
    ↓
Flink Job: EnrichOnlyFunction
    ↓
Semantic Embeddings Generated
```

