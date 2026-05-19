#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "==> Installing python3, curl, kubectl..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends python3 curl ca-certificates

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
    data=body, method="PUT",
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
    local file=$1 blob_name=$2
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

# Build cypher-shell arg string for running inside the source pod.
# Using -u/-p always; if password empty the server-side handshake will still proceed.
CYSHELL_AUTH="-u ${NEO4J_USERNAME:-neo4j}"
if [[ -n "${NEO4J_PASSWORD:-}" ]]; then
    CYSHELL_AUTH="${CYSHELL_AUTH} -p ${NEO4J_PASSWORD}"
fi

# Run a cypher query inside the source Neo4j pod using its own cypher-shell.
# This avoids any client/server Bolt protocol version mismatch.
run_cypher() {
    local query=$1
    local out=$2
    kubectl exec -n "$NEO4J_POD_NAMESPACE" "$NEO4J_POD_NAME" -- \
        bash -c "/var/lib/neo4j/bin/cypher-shell $CYSHELL_AUTH --format plain \"$query\"" \
        > "$out"
}

echo "==> Exporting Neo4j nodes and relationships (via kubectl exec into $NEO4J_POD_NAME)..."
run_cypher "MATCH (n) WITH labels(n) as labels, count(n) as count RETURN labels, count" \
    /tmp/neo4j_node_counts.csv
run_cypher "MATCH (n) RETURN id(n) as id, labels(n) as labels, properties(n) as properties" \
    /tmp/neo4j_nodes.csv
run_cypher "MATCH (a)-[r]->(b) RETURN id(a) as source_id, type(r) as relationship_type, properties(r) as properties, id(b) as target_id" \
    /tmp/neo4j_relationships.csv

NODE_COUNT=$(wc -l < /tmp/neo4j_nodes.csv)
REL_COUNT=$(wc -l < /tmp/neo4j_relationships.csv)

tar -czf /tmp/neo4j_export.tar.gz -C /tmp neo4j_nodes.csv neo4j_relationships.csv neo4j_node_counts.csv

upload_to_storage /tmp/neo4j_export.tar.gz "{{ .Values.source.neo4j_path }}/neo4j_export.tar.gz"

echo "Exported Neo4j: $NODE_COUNT nodes, $REL_COUNT relationships"
echo "Neo4j export completed successfully!"
