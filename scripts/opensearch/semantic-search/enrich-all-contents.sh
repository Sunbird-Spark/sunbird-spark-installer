#!/bin/bash
#
# Bulk enrich script: fetch all Content & Collection IDs from search service,
# batch them respecting max_identifiers limit, and trigger enrich API.
#

set -e

# Config
SEARCH_API="${SEARCH_API:-http://localhost:9000/v3/search}"
ENRICH_API="${ENRICH_API:-http://localhost:9000/v3/enrich}"
BATCH_SIZE="${BATCH_SIZE:-100}"
PAGE_SIZE=200

LOG_FILE="enrich-all-$(date +%Y%m%d_%H%M%S).log"
FAILED_FILE="enrich-failed-$(date +%Y%m%d_%H%M%S).txt"

echo "[$(date)] Starting bulk enrich job..." | tee -a "$LOG_FILE"

# Step 1: Query search service for all Content & Collection IDs
echo "[$(date)] Fetching identifiers from $SEARCH_API..." | tee -a "$LOG_FILE"

declare -a ALL_IDS
TOTAL_DOCS=0
OFFSET=0

while true; do
  RESPONSE=$(curl -s -X POST "$SEARCH_API" \
    -H "Content-Type: application/json" \
    -d "{
      \"request\": {
        \"filters\": {
          \"objectType\": [\"Content\", \"Collection\"]
        },
        \"limit\": $PAGE_SIZE,
        \"offset\": $OFFSET
      }
    }")

  # Extract identifiers
  IDS=$(echo "$RESPONSE" | jq -r '.result.content[]?.identifier // empty')
  HIT_COUNT=$(echo "$IDS" | grep -c . || true)

  if [ "$HIT_COUNT" -eq 0 ]; then
    echo "[$(date)] Search complete. Total IDs: $TOTAL_DOCS" | tee -a "$LOG_FILE"
    break
  fi

  while IFS= read -r id; do
    ALL_IDS+=("$id")
    ((TOTAL_DOCS++))
  done <<< "$IDS"

  echo "[$(date)] Fetched $HIT_COUNT IDs (total so far: $TOTAL_DOCS)" | tee -a "$LOG_FILE"
  ((OFFSET+=PAGE_SIZE))
done

# Step 3: Batch and enrich
echo "[$(date)] Starting enrich API calls (batch size: $BATCH_SIZE)..." | tee -a "$LOG_FILE"

SUCCEEDED=0
FAILED=0
BATCH_NUM=0

for ((i=0; i<${#ALL_IDS[@]}; i+=BATCH_SIZE)); do
  ((BATCH_NUM++))
  BATCH=("${ALL_IDS[@]:i:BATCH_SIZE}")

  # Build JSON array
  JSON_IDS=$(printf '%s\n' "${BATCH[@]}" | jq -R . | jq -s .)

  PAYLOAD=$(cat <<EOF
{
  "request": {
    "identifiers": $(echo "$JSON_IDS" | jq -c .)
  }
}
EOF
)

  BATCH_SIZE_ACTUAL=${#BATCH[@]}
  echo "[$(date)] Batch $BATCH_NUM: sending $BATCH_SIZE_ACTUAL IDs to $ENRICH_API..." | tee -a "$LOG_FILE"

  RESPONSE=$(curl -s -X POST "$ENRICH_API" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

  # Check response
  ERROR=$(echo "$RESPONSE" | jq -r '.error // empty')
  if [ -n "$ERROR" ]; then
    echo "[ERROR] Batch $BATCH_NUM failed: $ERROR" | tee -a "$LOG_FILE"
    printf '%s\n' "${BATCH[@]}" >> "$FAILED_FILE"
    ((FAILED+=BATCH_SIZE_ACTUAL))
  else
    SUCCESS_COUNT=$(echo "$RESPONSE" | jq -r '.result.count // 0')
    FAILED_IDS=$(echo "$RESPONSE" | jq -r '.result.failed[]? // empty')

    echo "[$(date)] Batch $BATCH_NUM: $SUCCESS_COUNT succeeded" | tee -a "$LOG_FILE"
    ((SUCCEEDED+=SUCCESS_COUNT))

    if [ -n "$FAILED_IDS" ]; then
      echo "$FAILED_IDS" >> "$FAILED_FILE"
      FAILED_COUNT=$(echo "$FAILED_IDS" | wc -l)
      ((FAILED+=FAILED_COUNT))
      echo "[$(date)] Batch $BATCH_NUM: $FAILED_COUNT IDs failed (logged to $FAILED_FILE)" | tee -a "$LOG_FILE"
    fi
  fi

  sleep 0.5  # Rate limit
done

echo "" | tee -a "$LOG_FILE"
echo "[$(date)] ===== ENRICH JOB COMPLETE =====" | tee -a "$LOG_FILE"
echo "Total processed: $((SUCCEEDED + FAILED))" | tee -a "$LOG_FILE"
echo "Succeeded: $SUCCEEDED" | tee -a "$LOG_FILE"
echo "Failed: $FAILED" | tee -a "$LOG_FILE"
echo "Batches: $BATCH_NUM" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
[ -f "$FAILED_FILE" ] && echo "Failed IDs: $FAILED_FILE" | tee -a "$LOG_FILE"
