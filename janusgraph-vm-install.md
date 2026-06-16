# JanusGraph VM Installation Guide

JanusGraph runs on the VM connecting to YugabyteDB (CQL port 9042). Config files are taken directly from the Helm chart.

---

## Prerequisites

- Ubuntu 22.04 VM
- Java 11+ installed
- YugabyteDB running and reachable on CQL port 9042

```bash
sudo apt update
sudo apt install -y openjdk-11-jdk wget unzip
java -version  # verify
```

---

## Step 1 — Download JanusGraph

```bash
wget https://github.com/JanusGraph/janusgraph/releases/download/v1.0.0/janusgraph-1.0.0.zip
unzip janusgraph-1.0.0.zip
cd janusgraph-1.0.0
```

---

## Step 2 — Download Config Files

Download directly from the repo:

```bash
BASE=https://raw.githubusercontent.com/Sunbird-Spark/sunbird-spark-installer/main/helmcharts/knowledgebb/charts/janusgraph/config

wget $BASE/janusgraph-cql.properties -O conf/janusgraph.properties
wget $BASE/gremlin-server.yaml       -O conf/gremlin-server.yaml
wget $BASE/schema_init.groovy        -O scripts/schema_init.groovy
wget $BASE/empty-sample.groovy       -O scripts/empty-sample.groovy
```

---

## Step 3 — Edit janusgraph.properties

Change `storage.hostname` from the Kubernetes service name to your YugabyteDB VM IP:

```properties
storage.hostname=<YOUR_YUGABYTE_VM_IP>
```

All other settings remain the same.

---

## Step 4 — Edit gremlin-server.yaml

Update the config and script paths from Bitnami paths to your local JanusGraph paths:

Change:
```yaml
graphs: {graph: /opt/bitnami/janusgraph/conf/janusgraph.properties}
scriptEngines:
  gremlin-groovy:
    plugins:
      org.apache.tinkerpop.gremlin.jsr223.ScriptFileGremlinPlugin:
        files:
          - /opt/bitnami/janusgraph/scripts/empty-sample.groovy
          - /opt/bitnami/janusgraph/scripts/schema_init.groovy
```

To (replace `/path/to/janusgraph-1.0.0` with actual path):
```yaml
graphs: {graph: /path/to/janusgraph-1.0.0/conf/janusgraph.properties}
scriptEngines:
  gremlin-groovy:
    plugins:
      org.apache.tinkerpop.gremlin.jsr223.ScriptFileGremlinPlugin:
        files:
          - /path/to/janusgraph-1.0.0/scripts/empty-sample.groovy
          - /path/to/janusgraph-1.0.0/scripts/schema_init.groovy
```

---

## Step 5 — Create empty-sample.groovy (if missing)

```bash
touch scripts/empty-sample.groovy
```

---

## Step 6 — CDC Extension (Optional)

For Change Data Capture support, install the JanusGraph CDC extension:

**Repository:** https://github.com/Sunbird-Knowlg/knowledge-platform-db-extensions/tree/develop/janusgraph-cdc-extension

Follow the build and deployment instructions in the above repository to enable CDC on JanusGraph.

---

## Step 7 — Start Gremlin Server

```bash
bin/gremlin-server.sh conf/gremlin-server.yaml
```

On startup, `schema_init.groovy` runs automatically via `ScriptFileGremlinPlugin`. It:
- Creates all property keys, vertex labels, edge labels
- Creates and enables all composite indexes
- Connects to YugabyteDB CQL and creates `janusgraph` keyspace if missing

Watch logs for `--- SCHEMA INITIALIZATION COMPLETE ---`

---

## Step 8 — Verify

Open a new terminal:

```bash
bin/gremlin.sh
# Inside gremlin console:
:remote connect tinkerpop.server conf/remote.yaml
:remote console
g.V().limit(1)   # returns [] if empty graph — means connected
```

---

## Port

JanusGraph listens on port `8182` (WebSocket). Set this in global-values.yaml:

```yaml
janusgraph:
  host: <VM_IP>
  port: 8182
```

---

## Firewall

Open port 8182 from EKS node CIDR to the VM:

```bash
sudo ufw allow from <EKS_NODE_CIDR> to any port 8182
```

---

## Helm Chart Reference

| Config File | Source (GitHub) | Local Destination |
|---|---|---|
| `janusgraph-cql.properties` | https://github.com/Sunbird-Spark/sunbird-spark-installer/blob/main/helmcharts/knowledgebb/charts/janusgraph/config/janusgraph-cql.properties | `conf/janusgraph.properties` |
| `gremlin-server.yaml` | https://github.com/Sunbird-Spark/sunbird-spark-installer/blob/main/helmcharts/knowledgebb/charts/janusgraph/config/gremlin-server.yaml | `conf/gremlin-server.yaml` |
| `schema_init.groovy` | https://github.com/Sunbird-Spark/sunbird-spark-installer/blob/main/helmcharts/knowledgebb/charts/janusgraph/config/schema_init.groovy | `scripts/schema_init.groovy` |
| `empty-sample.groovy` | https://github.com/Sunbird-Spark/sunbird-spark-installer/blob/main/helmcharts/knowledgebb/charts/janusgraph/config/empty-sample.groovy | `scripts/empty-sample.groovy` |

When deploying knowledgebb Helm chart, set `janusgraph.enabled: false` and point `global.janusgraph.host` to this VM IP.
