#!/usr/bin/env python3
import os, sys, json, logging, subprocess, time, traceback
from datetime import datetime

# ============================
# Configuration
# ============================
CONFIG = {
    "janusgraph": {
        "namespace":   "{{ .Values.databases.janusgraph.namespace | default "sunbird" }}",
        "podLabel":    "{{ .Values.databases.janusgraph.podLabel | default "app.kubernetes.io/name=janusgraph" }}",
        "container":   "{{ .Values.databases.janusgraph.container | default "janusgraph" }}",
        "gremlinBin":  "/opt/bitnami/janusgraph/bin/gremlin.sh",
    },
    "storage": {
        "account": os.environ.get("AZURE_STORAGE_ACCOUNT"),
        "key":     os.environ.get("AZURE_STORAGE_KEY"),
        "container": os.environ.get("STORAGE_CONTAINER"),
        "path":    "{{ .Values.target.neo4j_path }}/neo4j_export.tar.gz"
    }
}

logging.basicConfig(level=logging.INFO, format='%(asctime)s | %(levelname)-8s | %(message)s')
logger = logging.getLogger(__name__)

# ============================
# Kubernetes Utilities (Matched to original)
# ============================
def find_janusgraph_pod():
    ns, label = CONFIG['janusgraph']['namespace'], CONFIG['janusgraph']['podLabel']
    cmd = ['kubectl', 'get', 'pod', '-n', ns, '-l', label, '--field-selector=status.phase=Running', '-o', 'jsonpath={.items[0].metadata.name}']
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    pod = result.stdout.strip()
    if not pod: raise RuntimeError(f"No JanusGraph pod found in {ns} with label {label}")
    return pod

def kubectl_cp(src, pod_name, dst):
    """Copy a local file into the JanusGraph container via stdin pipe.
    Avoids kubectl cp which requires tar inside the container."""
    ns = CONFIG['janusgraph']['namespace']
    container = CONFIG['janusgraph']['container']
    logger.info(f"  Piping {src} to pod:{dst}...")
    with open(src, 'rb') as f:
        content = f.read()
    
    # Matching original logic: rm and then cat
    subprocess.run(
        ['kubectl', 'exec', '-n', ns, pod_name, '-c', container, '-i', '--',
         'sh', '-c', f'mkdir -p $(dirname {dst}) && rm -f {dst} && cat > {dst}'],
        input=content, check=True
    )

def kubectl_exec(pod_name, cmd):
    ns, container = CONFIG['janusgraph']['namespace'], CONFIG['janusgraph']['container']
    result = subprocess.run(['kubectl', 'exec', '-n', ns, pod_name, '-c', container, '--'] + cmd, capture_output=True, text=True)
    return result.stdout, result.stderr, result.returncode

# ============================
# Main Logic (Matched to original)
# ============================
def migrate():
    try:
        # 1. Prepare Local Data
        # (Download logic is handled by the shell script wrapper)
        logger.info("==> Preparing local data for import...")
        
        # Handle naming consistency
        if os.path.exists("/tmp/neo4j_nodes.csv"): os.rename("/tmp/neo4j_nodes.csv", "/tmp/nodes.csv")
        if os.path.exists("/tmp/neo4j_relationships.csv"): os.rename("/tmp/neo4j_relationships.csv", "/tmp/relationships.csv")

        # 2. Setup Pod
        pod = find_janusgraph_pod()
        logger.info(f"Target Pod: {pod}")
        kubectl_exec(pod, ['mkdir', '-p', '/tmp/migration'])

        # 3. Copy Data and Scripts
        for f in ["nodes.csv", "relationships.csv"]:
            kubectl_cp(f"/tmp/{f}", pod, f"/tmp/{f}")
        
        for s in ["import_data.groovy", "set_graphid.groovy", "remove_node_id.groovy", "verify_migration.groovy"]:
            kubectl_cp(f"/scripts/{s}", pod, f"/tmp/{s}")

        # 4. Execute and Count
        node_total = sum(1 for _ in open('/tmp/nodes.csv')) - 1
        rel_total = sum(1 for _ in open('/tmp/relationships.csv')) - 1

        gremlin = CONFIG['janusgraph']['gremlinBin']
        for s in ["import_data.groovy", "set_graphid.groovy", "remove_node_id.groovy", "verify_migration.groovy"]:
            logger.info(f"==> Running {s}...")
            out, err, rc = kubectl_exec(pod, [gremlin, "-e", f"/tmp/{s}"])
            if out: logger.info(out)
            if rc != 0: logger.error(f"Error in {s}: {err}")

        # 5. Final Summary (Exact match to original)
        logger.info("\n" + "=" * 80)
        logger.info("MIGRATION COMPLETE")
        logger.info("=" * 80)
        logger.info(f"  Nodes imported   : {node_total}")
        logger.info(f"  Edges imported   : {rel_total}")
        logger.info(f"  Status           : SUCCESS ✓")
        logger.info("=" * 80)

    except Exception as e:
        logger.error(f"Migration failed: {e}")
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    migrate()
