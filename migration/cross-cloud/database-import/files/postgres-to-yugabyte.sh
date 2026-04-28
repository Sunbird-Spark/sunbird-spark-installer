#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing python3, curl, postgresql-client..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends python3 curl ca-certificates postgresql-client

echo "==> Setting up blob downloader..."
cat > /usr/local/bin/azblob-download <<'PYEOF'
#!/usr/bin/env python3
"""Azure Blob Storage downloader using account key (stdlib only)."""
import sys, os, base64, hmac, hashlib, urllib.request
from datetime import datetime

account = os.environ["AZURE_STORAGE_ACCOUNT"]
key     = os.environ["AZURE_STORAGE_KEY"]
container, blob, outfile = sys.argv[1], sys.argv[2], sys.argv[3]

date = datetime.utcnow().strftime("%a, %d %b %Y %H:%M:%S GMT")
sts  = (f"GET\n\n\n\n\n\n\n\n\n\n\n\n"
        f"x-ms-date:{date}\nx-ms-version:2020-10-02\n/{account}/{container}/{blob}")
sig  = base64.b64encode(
    hmac.new(base64.b64decode(key), sts.encode("utf-8"), hashlib.sha256).digest()
).decode()

req = urllib.request.Request(
    f"https://{account}.blob.core.windows.net/{container}/{blob}",
    headers={
        "x-ms-date":      date,
        "x-ms-version":   "2020-10-02",
        "Authorization":  f"SharedKey {account}:{sig}",
    },
)
with urllib.request.urlopen(req) as r, open(outfile, "wb") as f:
    while True:
        chunk = r.read(1024 * 1024)
        if not chunk:
            break
        f.write(chunk)
print(f"Downloaded blob '{blob}' → {outfile}")
PYEOF
chmod +x /usr/local/bin/azblob-download

download_from_storage() {
    local blob_name=$1
    local file=$2
    case $STORAGE_TYPE in
        "azure")
            azblob-download "$STORAGE_CONTAINER" "$blob_name" "$file"
            ;;
        "gcp")
            echo "{{ .Values.target.serviceAccountKey }}" | base64 -d > /tmp/gcs-key.json
            gcloud auth activate-service-account --key-file=/tmp/gcs-key.json --project={{ .Values.target.projectId }}
            gsutil cp "gs://{{ .Values.target.bucket }}/$blob_name" "$file"
            ;;
        "aws")
            AWS_ACCESS_KEY_ID={{ .Values.target.accessKeyId }} \
            AWS_SECRET_ACCESS_KEY={{ .Values.target.secretAccessKey }} \
            aws s3 cp "s3://{{ .Values.target.s3Bucket }}/$blob_name" "$file"
            ;;
    esac
}

# Restore each database
{{- range .Values.databases.yugabytedb.databases }}
echo "==> Restoring database: {{ .name }}"

download_from_storage "{{ $.Values.target.postgresql_path }}/{{ .name }}.sql.gz" "/tmp/{{ .name }}.sql.gz"
gunzip -f /tmp/{{ .name }}.sql.gz

# Idempotent: drop + recreate DB so reruns produce a clean restore (no PK violations, no dupes)
echo "Dropping database {{ .name }} if it exists..."
PGPASSWORD="$POSTGRES_PASSWORD" psql \
    -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d postgres \
    -c "DROP DATABASE IF EXISTS {{ .name }};"

echo "Creating database {{ .name }}..."
PGPASSWORD="$POSTGRES_PASSWORD" psql \
    -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d postgres \
    -c "CREATE DATABASE {{ .name }};"

# Apply dump
PGPASSWORD="$POSTGRES_PASSWORD" psql \
    -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d {{ .name }} \
    -v ON_ERROR_STOP=0 \
    -f /tmp/{{ .name }}.sql

echo "    Restored {{ .name }} successfully"
{{- end }}

echo "PostgreSQL restore completed successfully!"