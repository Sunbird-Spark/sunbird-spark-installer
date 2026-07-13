#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing python3 and curl..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends python3 curl ca-certificates

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

echo "==> Downloading Neo4j export..."
download_from_storage "{{ .Values.target.neo4j_path }}/neo4j_export.tar.gz" "/tmp/neo4j_export.tar.gz"

cd /tmp
tar -xzf neo4j_export.tar.gz

# NOTE: Actual import into the target graph (JanusGraph) is handled by
# hierarchy-job.yaml (generate_hierarchy_relations.py), which reads these CSVs
# and emits Gremlin-compatible statements. This script only stages the data.
NODE_COUNT=$(wc -l < /tmp/neo4j_nodes.csv 2>/dev/null || echo 0)
REL_COUNT=$(wc -l < /tmp/neo4j_relationships.csv 2>/dev/null || echo 0)
echo "Staged: ${NODE_COUNT} nodes, ${REL_COUNT} relationships"

ls -lh /tmp/neo4j_*.csv

echo "Neo4j CSV export staged. Downstream hierarchy-fix job will import into JanusGraph."

# --- ADDING GROOVY MIGRATION LOGIC (Requested) ---
# We keep your 'neo4j_' files and create copies for the Groovy script
cp /tmp/neo4j_nodes.csv /tmp/nodes.csv
cp /tmp/neo4j_relationships.csv /tmp/relationships.csv

echo "==> Installing kubectl for remote JanusGraph import..."
apt-get update -qq && apt-get install -y -qq curl ca-certificates
curl -fL "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

if [[ "$1" == "--download-only" ]]; then
    echo "Staging only mode. Files downloaded to /tmp."
    return 0 2>/dev/null || exit 0
fi

# The rest of the script is now deprecated in favor of the Python script,
# but we leave it as a reference or fallback.
python3 /scripts/neo4j-to-janusgraph.py

# Helm variables for JanusGraph targeting
NS="{{ .Values.databases.janusgraph.namespace | default "sunbird" }}"
LABEL="{{ .Values.databases.janusgraph.podLabel | default "app.kubernetes.io/name=janusgraph" }}"
CONTAINER="{{ .Values.databases.janusgraph.container | default "janusgraph" }}"

echo "==> Finding JanusGraph pod..."
POD_NAME=$(kubectl get pod -n "$NS" -l "$LABEL" -o jsonpath='{.items[0].metadata.name}' --field-selector=status.phase=Running)

if [ -n "$POD_NAME" ]; then
    echo "Found JanusGraph pod: $POD_NAME. Starting bulk import..."
    kubectl exec -n "$NS" "$POD_NAME" -c "$CONTAINER" -- mkdir -p /tmp/migration
    kubectl cp /tmp/nodes.csv "$NS/$POD_NAME:/tmp/nodes.csv" -c "$CONTAINER"
    kubectl cp /tmp/relationships.csv "$NS/$POD_NAME:/tmp/relationships.csv" -c "$CONTAINER"
    kubectl cp /scripts/import_data.groovy "$NS/$POD_NAME:/tmp/import_data.groovy" -c "$CONTAINER"
    kubectl cp /scripts/set_graphid.groovy "$NS/$POD_NAME:/tmp/set_graphid.groovy" -c "$CONTAINER"
    kubectl cp /scripts/remove_node_id.groovy "$NS/$POD_NAME:/tmp/remove_node_id.groovy" -c "$CONTAINER"

    GREMLIN_BIN="/opt/bitnami/janusgraph/bin/gremlin.sh"
    # Match db-migration: default replaceExisting=false. Existing vertices skipped (no dupes),
    # new vertices get graphId via set_graphid. Source data static for migration → no refresh needed.
    kubectl exec -n "$NS" "$POD_NAME" -c "$CONTAINER" -- $GREMLIN_BIN -e /tmp/import_data.groovy
    kubectl exec -n "$NS" "$POD_NAME" -c "$CONTAINER" -- $GREMLIN_BIN -e /tmp/set_graphid.groovy
    kubectl exec -n "$NS" "$POD_NAME" -c "$CONTAINER" -- $GREMLIN_BIN -e /tmp/remove_node_id.groovy
    echo "Groovy bulk import completed."
else
    echo "WARNING: No JanusGraph pod found. Skipping Groovy bulk import."
fi
