#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing python3, pip, curl, cqlsh, kubectl..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends python3 python3-pip curl ca-certificates

if ! command -v cqlsh >/dev/null 2>&1; then
    python3 -m pip install --no-cache-dir --quiet cqlsh
fi

curl -fL --connect-timeout 30 --max-time 180 --retry 3 --retry-delay 5 \
    -o /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
kubectl version --client=true || true

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
# Canonicalized headers MUST be sorted by header name.
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

# Upload function
upload_to_storage() {
    local file=$1
    local blob_name=$2
    case $STORAGE_TYPE in
        "azure")
            azblob-upload "$STORAGE_CONTAINER" "$blob_name" "$file"
            ;;
        "gcp")
            echo "{{ $.Values.source.serviceAccountKey }}" | base64 -d > /tmp/gcs-key.json
            gcloud auth activate-service-account --key-file=/tmp/gcs-key.json --project={{ $.Values.source.projectId }}
            gsutil cp "$file" "gs://{{ $.Values.source.bucket }}/$blob_name"
            ;;
        "aws")
            AWS_ACCESS_KEY_ID={{ $.Values.source.accessKeyId }} \
            AWS_SECRET_ACCESS_KEY={{ $.Values.source.secretAccessKey }} \
            aws s3 cp "$file" "s3://{{ $.Values.source.s3Bucket }}/$blob_name"
            ;;
    esac
}

cqlsh_run() {
    local query=$1
    local auth_args=()

    if [[ -n "{{ .Values.databases.cassandra.username }}" && -n "${CASSANDRA_PASSWORD:-}" ]]; then
        auth_args=(-u "{{ .Values.databases.cassandra.username }}" -p "$CASSANDRA_PASSWORD")
    fi

    cqlsh {{ .Values.databases.cassandra.host }} \
          {{ .Values.databases.cassandra.port }} \
          "${auth_args[@]}" \
          -e "$query"
}

# Export each keyspace
{{- range .Values.databases.cassandra.keyspaces }}
echo "Exporting keyspace: {{ . }}"

# Create export directory
mkdir -p /tmp/cassandra_export/{{ . }}

# Dump keyspace schema via kubectl-exec into the source Cassandra pod.
# The pod's cqlsh is version-matched to the server, so client-side DESCRIBE works.
# (pip-installed cqlsh 6.x moved DESCRIBE to server-side and won't work against C* 3.x.)
echo "Dumping schema for keyspace {{ . }} (via kubectl exec into $CASSANDRA_POD_NAME)..."
kubectl exec -n "$CASSANDRA_POD_NAMESPACE" "$CASSANDRA_POD_NAME" -- \
    bash -c "cqlsh -e \"DESCRIBE KEYSPACE {{ . }};\"" \
    | sed -e '/^WARNING/d' -e '/^$/N;/^\n$/D' \
    > /tmp/cassandra_export/{{ . }}/schema.cql

# Get all tables in keyspace
cqlsh_run "SELECT table_name FROM system_schema.tables WHERE keyspace_name='{{ . }}';" \
    | awk '/^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*$/ { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 != "table_name") print }' \
    > /tmp/tables_{{ . }}.txt

# Export each table to CSV
TOTAL_ROWS=0
while read table; do
    if [[ -n "$table" ]]; then
        echo "Exporting table: {{ . }}.$table"

        # Export to CSV
        cqlsh_run "COPY {{ . }}.$table TO '/tmp/cassandra_export/{{ . }}/${table}.csv' WITH HEADER = true;"

        ROW_COUNT=$(cqlsh_run "SELECT COUNT(*) FROM {{ . }}.$table;" \
            | awk '/^[[:space:]]*[0-9]+[[:space:]]*$/ { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }')
        TOTAL_ROWS=$((TOTAL_ROWS + ${ROW_COUNT:-0}))
    fi
done < /tmp/tables_{{ . }}.txt

# Compress and upload (overwrite existing)
cd /tmp/cassandra_export/
tar -czf {{ . }}.tar.gz {{ . }}/

upload_to_storage /tmp/cassandra_export/{{ . }}.tar.gz "{{ $.Values.source.cassandra_path }}/{{ . }}.tar.gz"

echo "Exported keyspace {{ . }}: $TOTAL_ROWS rows"
{{- end }}

echo "Cassandra export completed successfully!"
