#!/bin/bash
set -euo pipefail

BACKUP_DATE=$(date +%Y-%m-%d_%H%M%S)
BACKUP_DIR="/tmp/backup"
YSQL_DIR="$BACKUP_DIR/ysql/$BACKUP_DATE"
YCQL_DIR="$BACKUP_DIR/ycql/$BACKUP_DATE"

mkdir -p "$YSQL_DIR" "$YCQL_DIR"

YB_HOST="${YB_HOST:-yb-tserver-service}"
YB_YSQL_PORT="${YB_YSQL_PORT:-5433}"
YB_YCQL_PORT="${YB_YCQL_PORT:-9042}"
YB_USER="${YB_USER:-yugabyte}"
YB_PASSWORD="${YB_PASSWORD:-yugabyte}"
YSQL_DATABASES="${YSQL_DATABASES:-keycloak quartz enc-keys registry sunbird}"
CLOUD_SERVICE="${CLOUD_SERVICE:-azure}"
CLOUD_STORAGE_AUTH_TYPE="${CLOUD_STORAGE_AUTH_TYPE:-workload_identity}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

echo "=== YugabyteDB Backup ==="
echo "Date     : $BACKUP_DATE"
echo "Cloud    : $CLOUD_SERVICE"
echo "Auth     : $CLOUD_STORAGE_AUTH_TYPE"

# ── YSQL Backup (pg_dump per database) ──────────────────────────────────────
echo ""
echo "--- YSQL Backup ---"
for db in $YSQL_DATABASES; do
    echo "Dumping YSQL database: $db"
    PGPASSWORD="$YB_PASSWORD" pg_dump \
        -h "$YB_HOST" \
        -p "$YB_YSQL_PORT" \
        -U "$YB_USER" \
        -F c \
        -d "$db" \
        -f "$YSQL_DIR/${db}.dump" && \
        echo "  ✓ $db dumped" || echo "  ✗ $db failed (skipping)"
done

# ── YCQL Backup (Python cassandra-driver) ────────────────────────────────────
echo ""
echo "--- YCQL Backup ---"
python3 /ycql_backup.py \
    --host "$YB_HOST" \
    --port "$YB_YCQL_PORT" \
    --output-dir "$YCQL_DIR" \
    --keyspaces "${YCQL_KEYSPACES:-}" && \
    echo "  ✓ YCQL backup complete" || echo "  ✗ YCQL backup failed"

# ── Upload to cloud storage ──────────────────────────────────────────────────
echo ""
echo "--- Uploading to $CLOUD_SERVICE ---"

upload_file() {
    local local_file="$1"
    local remote_path="$2"

    if [ "$CLOUD_SERVICE" == "azure" ]; then
        if [ "$CLOUD_STORAGE_AUTH_TYPE" == "workload_identity" ]; then
            az storage blob upload \
                --account-name "$AZURE_STORAGE_ACCOUNT" \
                --container-name "$AZURE_CONTAINER" \
                --name "$remote_path" \
                --file "$local_file" \
                --auth-mode login \
                --overwrite
        else
            az storage blob upload \
                --account-name "$AZURE_STORAGE_ACCOUNT" \
                --account-key "$AZURE_KEY" \
                --container-name "$AZURE_CONTAINER" \
                --name "$remote_path" \
                --file "$local_file" \
                --overwrite
        fi

    elif [ "$CLOUD_SERVICE" == "gcp" ]; then
        if [ "$CLOUD_STORAGE_AUTH_TYPE" == "access_key" ]; then
            export GOOGLE_APPLICATION_CREDENTIALS="/secrets/gcp-sa.json"
        fi
        gsutil cp "$local_file" "gs://${GCS_BUCKET}/${remote_path}"

    elif [ "$CLOUD_SERVICE" == "aws" ]; then
        aws s3 cp "$local_file" "s3://${S3_BUCKET}/${remote_path}"
    fi
}

# Upload YSQL dumps
for f in "$YSQL_DIR"/*.dump; do
    [ -f "$f" ] || continue
    remote="yugabyte-backups/ysql/$BACKUP_DATE/$(basename "$f")"
    upload_file "$f" "$remote" && echo "  ✓ uploaded $(basename "$f")"
done

# Upload YCQL files
find "$YCQL_DIR" -type f | while read -r f; do
    rel="${f#$BACKUP_DIR/}"
    remote="yugabyte-backups/$rel"
    upload_file "$f" "$remote" && echo "  ✓ uploaded $(basename "$f")"
done

# ── Cleanup old backups ──────────────────────────────────────────────────────
echo ""
echo "--- Cleaning backups older than $RETENTION_DAYS days ---"
CUTOFF_DATE=$(date -d "-${RETENTION_DAYS} days" +%Y-%m-%d 2>/dev/null || \
              date -v-${RETENTION_DAYS}d +%Y-%m-%d 2>/dev/null)

if [ "$CLOUD_SERVICE" == "azure" ]; then
    AUTH_ARGS="--auth-mode login"
    [ "$CLOUD_STORAGE_AUTH_TYPE" == "access_key" ] && \
        AUTH_ARGS="--account-key $AZURE_KEY"

    az storage blob delete-batch \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --source "$AZURE_CONTAINER" \
        --pattern "yugabyte-backups/*" \
        --if-unmodified-since "${CUTOFF_DATE}T00:00:00Z" \
        $AUTH_ARGS 2>/dev/null || true

elif [ "$CLOUD_SERVICE" == "gcp" ]; then
    gsutil -m rm -r "gs://${GCS_BUCKET}/yugabyte-backups/$(date -d "-${RETENTION_DAYS} days" +%Y-%m-%d)*" 2>/dev/null || true

elif [ "$CLOUD_SERVICE" == "aws" ]; then
    aws s3 rm "s3://${S3_BUCKET}/yugabyte-backups/" \
        --recursive \
        --exclude "*" \
        --include "$(date -d "-${RETENTION_DAYS} days" +%Y-%m-%d)*" 2>/dev/null || true
fi

echo ""
echo "=== Backup complete: $BACKUP_DATE ==="
