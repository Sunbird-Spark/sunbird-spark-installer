#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing python3, curl, postgresql-client..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends python3 curl ca-certificates postgresql-client

echo "==> Setting up blob uploader..."
cat > /usr/local/bin/azblob-upload <<'PYEOF'
#!/usr/bin/env python3
"""Azure Blob Storage uploader using account key (stdlib only)."""
import sys, os, base64, hmac, hashlib, urllib.request
from datetime import datetime

account = os.environ["AZURE_STORAGE_ACCOUNT"]
key     = os.environ["AZURE_STORAGE_KEY"]
container, blob, infile = sys.argv[1], sys.argv[2], sys.argv[3]

with open(infile, "rb") as f:
    body = f.read()
length = len(body)
ctype  = "application/octet-stream"

date = datetime.utcnow().strftime("%a, %d %b %Y %H:%M:%S GMT")
sts  = (
    f"PUT\n\n\n{length}\n\n{ctype}\n\n\n\n\n\n\n"
    f"x-ms-blob-type:BlockBlob\nx-ms-date:{date}\nx-ms-version:2020-10-02\n"
    f"/{account}/{container}/{blob}"
)
sig  = base64.b64encode(
    hmac.new(base64.b64decode(key), sts.encode("utf-8"), hashlib.sha256).digest()
).decode()

req = urllib.request.Request(
    f"https://{account}.blob.core.windows.net/{container}/{blob}",
    data=body,
    method="PUT",
    headers={
        "x-ms-date":       date,
        "x-ms-version":    "2020-10-02",
        "x-ms-blob-type":  "BlockBlob",
        "Content-Type":    ctype,
        "Content-Length":  str(length),
        "Authorization":   f"SharedKey {account}:{sig}",
    },
)
with urllib.request.urlopen(req) as r:
    if r.status not in (200, 201):
        raise SystemExit(f"Upload failed: HTTP {r.status}")
print(f"Uploaded {infile} → {container}/{blob} ({length} bytes)")
PYEOF
chmod +x /usr/local/bin/azblob-upload

upload_to_storage() {
    local file=$1
    local blob_name=$2
    case $STORAGE_TYPE in
        "azure")
            azblob-upload "$STORAGE_CONTAINER" "$blob_name" "$file"
            ;;
        "gcp")
            echo "{{ .Values.source.serviceAccountKey }}" | base64 -d > /tmp/gcs-key.json
            gcloud auth activate-service-account --key-file=/tmp/gcs-key.json --project={{ .Values.source.projectId }}
            gsutil cp "$file" "gs://{{ .Values.source.bucket }}/$blob_name"
            ;;
        "aws")
            AWS_ACCESS_KEY_ID={{ .Values.source.accessKeyId }} \
            AWS_SECRET_ACCESS_KEY={{ .Values.source.secretAccessKey }} \
            aws s3 cp "$file" "s3://{{ .Values.source.s3Bucket }}/$blob_name"
            ;;
    esac
}

# Export each database
{{- range .Values.databases.postgresql.databases }}
echo "==> Exporting database: {{ .name }}"

PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
    -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    --no-owner \
    --no-privileges \
    --clean --if-exists \
    -f /tmp/{{ .name }}.sql \
    {{ .name }}

gzip -f /tmp/{{ .name }}.sql
upload_to_storage /tmp/{{ .name }}.sql.gz "{{ $.Values.source.postgresql_path }}/{{ .name }}.sql.gz"

echo "    Exported {{ .name }}"
{{- end }}

echo "PostgreSQL export completed successfully!"
