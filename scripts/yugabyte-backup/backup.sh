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
YSQL_DATABASES="${YSQL_DATABASES:-keycloak registry quartz enc-keys kong portal superset sunbird}"
CLOUD_SERVICE="${CLOUD_SERVICE:-azure}"
CLOUD_STORAGE_AUTH_TYPE="${CLOUD_STORAGE_AUTH_TYPE:-workload_identity}"
RETENTION_DAYS="${RETENTION_DAYS:-56}"

echo "=== YugabyteDB Backup ==="
echo "Date     : $BACKUP_DATE"
echo "Cloud    : $CLOUD_SERVICE"
echo "Auth     : $CLOUD_STORAGE_AUTH_TYPE"

# ── YSQL Backup (pg_dump per database, plain SQL + DROP/CREATE, gzipped) ─────
echo ""
echo "--- YSQL Backup ---"
for db in $YSQL_DATABASES; do
    echo "Dumping YSQL database: $db"
    PGPASSWORD="$YB_PASSWORD" pg_dump \
        -h "$YB_HOST" \
        -p "$YB_YSQL_PORT" \
        -U "$YB_USER" \
        --format=plain \
        --clean \
        --if-exists \
        --create \
        -d "$db" | gzip > "$YSQL_DIR/${db}.sql.gz" && \
        echo "  ✓ $db dumped" || echo "  ✗ $db failed (skipping)"
done

# ── YCQL Backup (Python cassandra-driver, then tar+gzip per keyspace) ───────
echo ""
echo "--- YCQL Backup ---"
python3 /ycql_backup.py \
    --host "$YB_HOST" \
    --port "$YB_YCQL_PORT" \
    --output-dir "$YCQL_DIR" \
    --keyspaces "${YCQL_KEYSPACES:-}" && \
    echo "  ✓ YCQL backup complete" || echo "  ✗ YCQL backup failed"

for ks_dir in "$YCQL_DIR"/*/; do
    [ -d "$ks_dir" ] || continue
    ks=$(basename "$ks_dir")
    tar -czf "$YCQL_DIR/${ks}.tar.gz" -C "$YCQL_DIR" "$ks"
    echo "  ✓ $ks archived"
done

# ── Upload to cloud storage ──────────────────────────────────────────────────
echo ""
echo "--- Uploading to $CLOUD_SERVICE ---"

# The az CLI keeps its own session cache and doesn't auto-discover workload
# identity — unlike SDK-based tools (DefaultAzureCredential), it needs one
# explicit login exchanging the federated token for a real AAD token first.
if [ "$CLOUD_SERVICE" == "azure" ] && [ "$CLOUD_STORAGE_AUTH_TYPE" == "OIDC" ]; then
    az login --service-principal \
        -u "$AZURE_CLIENT_ID" \
        -t "$AZURE_TENANT_ID" \
        --federated-token "$(cat "$AZURE_FEDERATED_TOKEN_FILE")" \
        >/dev/null
    echo "✓ Logged in to Azure via workload identity"
fi

upload_file() {
    local local_file="$1"
    local remote_path="$2"

    if [ "$CLOUD_SERVICE" == "azure" ]; then
        if [ "$CLOUD_STORAGE_AUTH_TYPE" == "OIDC" ]; then
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
        if [ "$CLOUD_STORAGE_AUTH_TYPE" != "OIDC" ]; then
            export GOOGLE_APPLICATION_CREDENTIALS="/secrets/gcp-sa.json"
        fi
        gsutil cp "$local_file" "gs://${GCS_BUCKET}/${remote_path}"

    elif [ "$CLOUD_SERVICE" == "aws" ]; then
        aws s3 cp "$local_file" "s3://${S3_BUCKET}/${remote_path}"
    fi
}

# Upload YSQL dumps: ysql/<db-name>/<timestamp>.sql.gz
for f in "$YSQL_DIR"/*.sql.gz; do
    [ -f "$f" ] || continue
    db=$(basename "$f" .sql.gz)
    remote="yugabyte-backups/ysql/${db}/${BACKUP_DATE}.sql.gz"
    upload_file "$f" "$remote" && echo "  ✓ uploaded $db"
done

# Upload YCQL archives: ycql/<keyspace-name>/<timestamp>.tar.gz
for f in "$YCQL_DIR"/*.tar.gz; do
    [ -f "$f" ] || continue
    ks=$(basename "$f" .tar.gz)
    remote="yugabyte-backups/ycql/${ks}/${BACKUP_DATE}.tar.gz"
    upload_file "$f" "$remote" && echo "  ✓ uploaded $ks"
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
