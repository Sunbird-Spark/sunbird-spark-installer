#!/usr/bin/env python3
"""
Neo4j to JanusGraph Migration using Python

Phase 1 (Python): Reads nodes and relationships from Neo4j via Bolt → writes CSVs
Phase 2 (Groovy): kubectl exec → runs import_data.groovy inside JanusGraph pod
         (uses JanusGraphFactory.open directly — no WebSocket, no DROP)

CSV formats expected by import_data.groovy:
  nodes.csv:         node_id,"label",{props_json}
  relationships.csv: from_id,"rel_type",to_id,{props_json}
"""

import sys
import json
import logging
import os
import subprocess
import time
import traceback
from datetime import datetime
from neo4j.v1 import GraphDatabase, basic_auth

# ============================
# Configuration
# ============================
CONFIG = {
    "neo4j": {
        "host": "{{ .Values.neo4j.host }}",
        "port": {{ .Values.neo4j.port }},
        "username": "{{ .Values.neo4j.username }}",
        "password": "{{ .Values.neo4j.password }}",
        "nodeLabels": {{ .Values.neo4j.nodeLabels | toJson }},
        "relationships": {{ .Values.neo4j.relationships | toJson }},
    },
    "janusgraph": {
        "namespace":   "{{ .Values.janusgraph.namespace }}",
        "podLabel":    "{{ .Values.janusgraph.podLabel }}",
        "container":   "{{ .Values.janusgraph.container }}",
        "gremlinBin":  "/opt/bitnami/janusgraph/bin/gremlin.sh",
    },
}

NODES_CSV      = "/tmp/nodes.csv"
RELS_CSV       = "/tmp/relationships.csv"
IMPORT_GROOVY  = "/scripts/import_data.groovy"
VERIFY_GROOVY  = "/scripts/verify_migration.groovy"
SET_GRAPHID_GROOVY = "/scripts/set_graphid.groovy"

# ============================
# Logging
# ============================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)-8s | %(message)s',
    handlers=[
        logging.FileHandler('/var/log/migration/migration.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)


# ============================
# Neo4j Connection with Retry
# ============================
def neo4j_connect(retries=5, delay=10):
    """Connect to Neo4j with retry/backoff — mirrors cassandra_connect()"""
    uri  = f"bolt://{CONFIG['neo4j']['host']}:{CONFIG['neo4j']['port']}"
    pwd  = CONFIG['neo4j']['password']
    auth = basic_auth(CONFIG['neo4j']['username'], pwd) if pwd else None
    last_err = None
    for attempt in range(1, retries + 1):
        try:
            driver = GraphDatabase.driver(uri, auth=auth)
            with driver.session() as s:
                s.run("RETURN 1")
            logger.info(f"  Connected to Neo4j at {uri}")
            return driver
        except Exception as e:
            last_err = e
            if attempt < retries:
                logger.warning(f"  Neo4j connect attempt {attempt}/{retries} failed — retrying in {delay}s")
                time.sleep(delay)
    raise last_err


# ============================
# Auto-discover Labels and Rels
# ============================
def discover_labels_and_rels(driver):
    with driver.session() as s:
        labels = [r['label'] for r in s.run("CALL db.labels() YIELD label RETURN label")]
        rels   = [r['relationshipType'] for r in
                  s.run("CALL db.relationshipTypes() YIELD relationshipType RETURN relationshipType")]
    logger.info(f"  Discovered {len(labels)} node labels: {labels}")
    logger.info(f"  Discovered {len(rels)} relationship types: {rels}")
    return labels, rels


# ============================
# Phase 1: Export Neo4j → CSV
# ============================
def export_nodes(driver, node_labels):
    """
    Export nodes to CSV in format expected by import_data.groovy:
      node_id,"label",{props_json}
    """
    os.makedirs("/tmp", exist_ok=True)
    total       = 0
    label_counts = {}

    with open(NODES_CSV, 'w') as f:
        f.write("node_id,label,props\n")   # header (import_data.groovy skips idx==1)

        with driver.session() as session:
            for label in node_labels:
                count  = 0
                result = session.run(f"MATCH (n:{label}) RETURN id(n) AS node_id, n")

                for record in result:
                    node_id  = int(record['node_id'])
                    node_obj = record['n']

                    props = {}
                    for key in node_obj.keys():
                        val = node_obj[key]
                        if isinstance(val, bool):
                            props[key] = val
                        elif isinstance(val, int):
                            props[key] = int(val)
                        elif isinstance(val, float):
                            props[key] = float(val)
                        else:
                            props[key] = str(val)

                    # Format: node_id,"label",{json}  — label must be quoted so
                    # import_data.groovy's regex splits correctly
                    f.write(f'{node_id},"{label}",{json.dumps(props)}\n')
                    total += 1
                    count += 1

                label_counts[label] = count

    logger.info(f"  Exported {total} nodes to {NODES_CSV}")
    return total, label_counts


def export_relationships(driver, rel_types):
    """
    Export relationships to CSV in format expected by import_data.groovy:
      from_id,"rel_type",to_id,{props_json}
    """
    total     = 0
    rel_counts = {}

    with open(RELS_CSV, 'w') as f:
        f.write("from_id,rel_type,to_id,props\n")   # header

        with driver.session() as session:
            for rel_type in rel_types:
                count  = 0
                result = session.run(
                    f"MATCH (a)-[r:{rel_type}]->(b) "
                    f"RETURN id(a) AS from_id, id(b) AS to_id, properties(r) AS props"
                )
                for record in result:
                    from_id   = int(record['from_id'])
                    to_id     = int(record['to_id'])
                    rel_props = dict(record['props']) if record['props'] else {}
                    # Format: from_id,"rel_type",to_id,{props}
                    f.write(f'{from_id},"{rel_type}",{to_id},{json.dumps(rel_props)}\n')
                    total += 1
                    count += 1

                rel_counts[rel_type] = count

    logger.info(f"  Exported {total} relationships to {RELS_CSV}")
    return total, rel_counts


# ============================
# Phase 2: kubectl exec inside JanusGraph pod
# ============================
def find_janusgraph_pod():
    """Find the running JanusGraph pod name via kubectl."""
    ns    = CONFIG['janusgraph']['namespace']
    label = CONFIG['janusgraph']['podLabel']
    result = subprocess.run(
        ['kubectl', 'get', 'pod', '-n', ns,
         '-l', label,
         '--field-selector=status.phase=Running',
         '-o', 'jsonpath={.items[0].metadata.name}'],
        capture_output=True, text=True, check=True
    )
    pod = result.stdout.strip()
    if not pod:
        raise RuntimeError(f"No running JanusGraph pod found with label '{label}' in namespace '{ns}'")
    logger.info(f"  Found JanusGraph pod: {pod}")
    return pod


def kubectl_cp(src, pod_name, dst):
    """Copy a local file into the JanusGraph container via stdin pipe.
    Avoids kubectl cp which requires tar inside the container."""
    ns        = CONFIG['janusgraph']['namespace']
    container = CONFIG['janusgraph']['container']
    with open(src, 'rb') as f:
        content = f.read()
    subprocess.run(
        ['kubectl', 'exec', '-n', ns, pod_name, '-c', container, '-i', '--',
         'sh', '-c', f'rm -rf {dst} && cat > {dst}'],
        input=content, check=True
    )
    # Verify file landed in the container
    chk_out, chk_err, chk_rc = kubectl_exec(pod_name, ['ls', '-la', dst])
    if chk_rc != 0:
        raise RuntimeError(f"kubectl_cp: file {dst} not found in pod after copy: {chk_err}")
    logger.info(f"  Copied {src} → pod:{dst}  ({chk_out.strip()})")


def kubectl_exec(pod_name, cmd, timeout=3600):
    """Run a command inside the JanusGraph container and return its output."""
    ns        = CONFIG['janusgraph']['namespace']
    container = CONFIG['janusgraph']['container']
    result = subprocess.run(
        ['kubectl', 'exec', '-n', ns, pod_name, '-c', container, '--'] + cmd,
        capture_output=True, text=True, timeout=timeout
    )
    return result.stdout, result.stderr, result.returncode


def run_groovy_script(pod_name, remote_script_path, extra_args=None):
    """Execute a Groovy script via gremlin.sh inside the JanusGraph pod."""
    gremlin_bin = CONFIG['janusgraph']['gremlinBin']
    cmd = [gremlin_bin, '-e', remote_script_path]
    if extra_args:
        cmd += extra_args

    logger.info(f"  Running: {' '.join(cmd)}")
    stdout, stderr, rc = kubectl_exec(pod_name, cmd)

    for line in (stdout + stderr).splitlines():
        logger.info(f"  [gremlin] {line}")

    return stdout, stderr, rc


def import_and_verify(pod_name):
    """
    Copy CSVs + groovy scripts to JG pod and run import, then verify.
    Returns (import_ok, verify_ok).
    """
    # Create migration dir in pod
    kubectl_exec(pod_name, ['mkdir', '-p', '/tmp/migration'])

    # Copy CSVs to /tmp/ (import_data.groovy reads from /tmp/nodes.csv and /tmp/relationships.csv)
    kubectl_cp(NODES_CSV,         pod_name, '/tmp/nodes.csv')
    kubectl_cp(RELS_CSV,          pod_name, '/tmp/relationships.csv')
    kubectl_cp(IMPORT_GROOVY,     pod_name, '/tmp/import_data.groovy')
    kubectl_cp(VERIFY_GROOVY,     pod_name, '/tmp/verify_migration.groovy')
    kubectl_cp(SET_GRAPHID_GROOVY, pod_name, '/tmp/set_graphid.groovy')

    # Run import
    logger.info("\n  --- Running import_data.groovy ---")
    _, _, rc = run_groovy_script(pod_name, '/tmp/import_data.groovy')
    import_ok = (rc == 0)
    if not import_ok:
        logger.error(f"  import_data.groovy exited with code {rc}")

    # Set graphId=domain for all migrated vertices
    logger.info("\n  --- Running set_graphid.groovy ---")
    _, _, rc_g = run_groovy_script(pod_name, '/tmp/set_graphid.groovy')
    if rc_g != 0:
        logger.error(f"  set_graphid.groovy exited with code {rc_g}")

    # Run verify
    logger.info("\n  --- Running verify_migration.groovy ---")
    _, _, rc_v = run_groovy_script(pod_name, '/tmp/verify_migration.groovy')
    verify_ok = (rc_v == 0)

    return import_ok, verify_ok


# ============================
# Main Migration
# ============================
def migrate_all():
    start = datetime.now()
    logger.info("=" * 80)
    logger.info("Neo4j → JanusGraph Migration (Python + Spark)")
    logger.info("=" * 80)
    logger.info(f"  Source: Neo4j  {CONFIG['neo4j']['host']}:{CONFIG['neo4j']['port']}")
    logger.info(f"  Target: JanusGraph pod (namespace={CONFIG['janusgraph']['namespace']},"
                f" label={CONFIG['janusgraph']['podLabel']})")

    # Connect to Neo4j
    driver = neo4j_connect()

    # Resolve labels and rel types
    node_labels = CONFIG['neo4j']['nodeLabels'] or []
    rel_types   = CONFIG['neo4j']['relationships'] or []

    if not node_labels and not rel_types:
        logger.info("  Auto-discovering labels and rel types from Neo4j...")
        node_labels, rel_types = discover_labels_and_rels(driver)
    elif not node_labels:
        logger.info("  Auto-discovering node labels from Neo4j...")
        node_labels, _ = discover_labels_and_rels(driver)
    elif not rel_types:
        logger.info("  Auto-discovering relationship types from Neo4j...")
        _, rel_types = discover_labels_and_rels(driver)

    migration_stats = {
        "start_time":  start.isoformat(),
        "node_labels": node_labels,
        "rel_types":   rel_types,
    }

    # Phase 1: Export Neo4j → CSVs
    logger.info(f"\n[1/3] Exporting Neo4j data to CSV")
    logger.info(f"      Labels    : {node_labels}")
    logger.info(f"      Rel types : {rel_types}")

    node_total, _ = export_nodes(driver, node_labels)
    rel_total,  _ = export_relationships(driver, rel_types)
    driver.close()

    migration_stats["exported_nodes"] = node_total
    migration_stats["exported_rels"]  = rel_total

    # Phase 2: Import via kubectl exec + Groovy
    logger.info(f"\n[2/3] Importing into JanusGraph via kubectl exec")
    pod_name = find_janusgraph_pod()
    import_ok, verify_ok = import_and_verify(pod_name)

    # Summary
    duration = (datetime.now() - start).total_seconds()
    migration_stats["duration_seconds"] = duration
    migration_stats["import_ok"]  = import_ok
    migration_stats["verify_ok"]  = verify_ok

    logger.info("\n" + "=" * 80)
    logger.info("MIGRATION COMPLETE")
    logger.info("=" * 80)
    logger.info(f"  Nodes exported   : {node_total}")
    logger.info(f"  Edges exported   : {rel_total}")
    logger.info(f"  Import status    : {'SUCCESS ✓' if import_ok else 'FAILED ✗'}")
    logger.info(f"  Verify status    : {'SUCCESS ✓' if verify_ok else 'FAILED ✗'}")
    logger.info(f"  Duration         : {duration:.2f}s ({duration/60:.1f}m)")
    logger.info("=" * 80)

    # Save report
    os.makedirs('/var/log/migration', exist_ok=True)
    with open('/var/log/migration/migration_report.json', 'w') as f:
        json.dump(migration_stats, f, indent=2)

    return import_ok and verify_ok


# ============================
# Entry Point
# ============================
if __name__ == "__main__":
    try:
        success = migrate_all()
        sys.exit(0 if success else 1)

    except Exception as e:
        logger.error(f"Fatal error: {str(e)}")
        logger.error(traceback.format_exc())
        sys.exit(1)
