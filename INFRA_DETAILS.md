# Sunbird-ED Infrastructure Details

Per-component resource breakdown for the sunbird-spark-installer. All resource values are sourced from [helmcharts/global-resources.yaml](helmcharts/global-resources.yaml).

---

## Node Configuration

| Cloud Provider | Node Count | VM / Machine Type | vCPU per Node | RAM per Node | Total vCPU | Total RAM |
|----------------|-----------|-------------------|---------------|--------------|------------|-----------|
| **Azure (AKS)** | 2 | Standard_B16as_v2 | 16 | 64 GB | 32 | 128 GB |

---

## Databases

All databases run as Kubernetes workloads inside the cluster.

### YugabyteDB

Primary distributed database used across all building blocks. Deployed as **6 pods** (3 masters + 3 tservers).

| Component | Pods | CPU req / limit | Memory req / limit | Disk per pod |
|-----------|------|-----------------|--------------------|--------------|
| Master | 3 | 2 / 2 | 2 Gi / 2 Gi | 20 Gi (2 PVCs × 10 Gi) |
| TServer | 3 | 2 / 2 | 4 Gi / 4 Gi | 20 Gi (2 PVCs × 10 Gi) |

| Port | Usage |
|------|-------|
| 9042 | CQL (Cassandra-compatible) |
| 5433 | PostgreSQL-compatible (YSQL) |

**Databases provisioned per building block:**

| Building Block | Databases |
|----------------|-----------|
| EdBB | kong, superset, registry, portal |
| LearnBB | keycloak, quartz, enc-keys, registry |
| ObsrvBB | superset |
| KnowledgeBB | hierarchy_store, content_store (CQL keyspaces) |

### Redis (Optional)

**1 pod** (master only, replica disabled). Can be disabled if an external Redis is used.

| Component | CPU req / limit | Memory req / limit | Disk |
|-----------|-----------------|--------------------|------|
| Master | 0.5 / 0.5 | 1 Gi / 2 Gi | 25 Gi |

Port: **6379**

### Elasticsearch

Used by KnowledgeBB and LearnBB.

| Parameter | Value |
|-----------|-------|
| Pods | 1 master node |
| CPU request / limit | 1 / 2 |
| Memory request / limit | 2 Gi / 4 Gi |
| JVM Heap | 2 G |
| Disk | 25 Gi |
| Port | 9200 |

### JanusGraph

Used by KnowledgeBB. Storage backend is YugabyteDB (CQL) — no local disk.

| Parameter | Value |
|-----------|-------|
| Pods | 1 |
| CPU request / limit | 1 / 3 |
| Memory request / limit | 3 Gi / 6 Gi |
| Persistence | None (uses external YugabyteDB) |
| Port | 8182 |

---

## Flink Jobs

Each Flink job runs with a **JobManager** pod and a **TaskManager** pod (2 pods per job).

**Common resource per job:**

| Parameter | Value |
|-----------|-------|
| CPU request / limit | 100m / 1 |
| Memory request / limit | 1024 Mi / 2048 Mi |
| JobManager heap | 1024 m |
| JobManager process size | 1600 m |
| TaskManager heap | 1024 m |
| TaskManager process size | 1700 m |
| TaskManager replicas | 1 |

### KnowledgeBB Flink Jobs

| Job | Enabled | Description |
|-----|---------|-------------|
| `transaction-event-processor` | Yes | Processes learning graph events, generates audit telemetry and composite search index |
| `knowlg-publish` | Yes | Handles content/collection publish pipeline |
| `asset-enrichment` | No (disabled by default) | Video/image enrichment; enable via `enable_asset_enrichment: true` |

### LearnBB Flink Jobs

| Job | Enabled | Description |
|-----|---------|-------------|
| `collection-certificate-generator` | Yes | Generates course completion certificates |
| `notification-job` | Yes | Sends FCM / SMS / email notifications |
| `user-deletion-cleanup` | Yes | Cleans up user data on account deletion |

---

## Application Services

All services run with **1 replica** by default. Most services use CPU 100m / 1 core and memory 100 Mi / 1–2 Gi.

| Building Block | Services | Count |
|----------------|----------|-------|
| EdBB | echo, knowledge-mw, player (portal), kong (API gateway), nginx-public-ingress ,kafka| 5 |
| KnowledgeBB | knowlg-service, search-service | 2 |
| LearnBB | lern-service, keycloak+adminutil, cert (cert-service, cert-registry, certificateapi, certificatesign), registry (Sunbird-RC) | 4 |
| ObsrvBB | telemetry-service,superset | 1 |
| Monitoring | grafana-alloy, loki, monitoring-grafana, prometheus | 4 |
| **Total** | | **17** |

#### Kafka

Runs in KRaft mode. **3 controller pods** (each acts as broker + controller).

| Parameter | Value |
|-----------|-------|
| Pods | 3 (controllers) |
| CPU request / limit | 750m / 1 |
| Memory request / limit | 1024 Mi / 2048 Mi |
| Disk per pod | 8 Gi |
| Port | 9092 |

### Velero (Backup & Disaster Recovery)

Runs as a deployment + node-agent daemonset (1 pod per node).

| Component | CPU req / limit | Memory req / limit |
|-----------|-----------------|-------------------|
| velero (deployment) | 100m / 100m | 512 Mi / 1024 Mi |
| node-agent (daemonset) | 500m / 1000m | 512 Mi / 1024 Mi |

---

## Total Resource Summary (Base Platform)

| Category | CPU Request | CPU Limit | Memory Request | Memory Limit | Disk |
|----------|-------------|-----------|----------------|--------------|------|
| Databases (excl. optional Redis) | ~15 cores | ~18 cores | ~23 Gi | ~28 Gi | ~195 Gi |
| Flink Jobs (5 enabled) | ~1 core | ~10 cores | ~10 Gi | ~20 Gi | — |
| Application Services + Kafka (22 services) | ~5 cores | ~22 cores | ~6.5 Gi | ~26 Gi | ~24 Gi |
| **Grand Total** | **~21 cores** | **~50 cores** | **~40 Gi** | **~74 Gi** | **~219 Gi** |

**Disk breakdown:**
- YugabyteDB: 6 pods × 2 PVCs × 10 Gi = 120 Gi
- Elasticsearch: 1 pod × 25 Gi = 25 Gi
- Prometheus: 1 × 25 Gi = 25 Gi
- Loki: 1 × 25 Gi = 25 Gi
- Kafka: 3 pods × 8 Gi = 24 Gi *(counted under Application Services)*
- **Total disk: ~219 Gi**
- Redis: 1 pod × 25 Gi = 25 Gi *(optional — not included in total above)*

---

## Optional Addons

### DIAL Addon

Enables DIAL (Digital Infrastructure for Augmented Learning) — QR code–based content linking.

| Component | Pods | CPU req / limit | Memory req / limit |
|-----------|------|-----------------|--------------------|
| dial (service) | 1 | 100m / 1 | 100 Mi / 1024 Mi |
| dialcode-context-updater (Flink JM + TM) | 2 | 100m / 1 each | 500 Mi / 2048 Mi each |
| qrcode-image-generator (Flink JM + TM) | 2 | 100m / 1 each | 500 Mi / 2048 Mi each |
| **DIAL Total** | **5** | **~0.5 cores / ~5 cores** | **~2 Gi / ~9 Gi** |

### Discussion Forum Addon

Adds community discussion threads (NodeBB) and group management.

| Component | Pods | CPU req / limit | Memory req / limit |
|-----------|------|-----------------|--------------------|
| discussionmw | 1 | 100m / 1 | 100 Mi / 1 Gi |
| nodebb | 1 | 100m / 1 | 100 Mi / 2 Gi |
| groups | 1 | 100m / 1 | 100 Mi / 1 Gi |
| **Discussion Forum Total** | **3** | **~0.3 cores / ~3 cores** | **~0.3 Gi / ~4 Gi** |

### Video Stream Generator Addon

Flink job that converts uploaded videos to HLS streaming format.

| Component | Pods | CPU req / limit | Memory req / limit |
|-----------|------|-----------------|--------------------|
| video-stream-generator (Flink JM + TM) | 2 | 100m / 1 each | 500 Mi / 2048 Mi each |
| **Video Stream Total** | **2** | **~0.2 cores / ~2 cores** | **~1 Gi / ~4 Gi** |

### Total Resource Summary with All Addons

| Category | CPU Request | CPU Limit | Memory Request | Memory Limit | Disk |
|----------|-------------|-----------|----------------|--------------|------|
| Base Platform | ~21 cores | ~50 cores | ~40 Gi | ~74 Gi | ~219 Gi |
| DIAL Addon | ~0.5 cores | ~5 cores | ~2 Gi | ~9 Gi | — |
| Discussion Forum Addon | ~0.3 cores | ~3 cores | ~0.3 Gi | ~4 Gi | — |
| Video Stream Generator Addon | ~0.2 cores | ~2 cores | ~1 Gi | ~4 Gi | — |
| **Grand Total (all addons)** | **~22 cores** | **~60 cores** | **~43 Gi** | **~91 Gi** | **~219 Gi** |

> All addons together add only ~1 CPU core and ~3 Gi of memory requests. **No additional nodes are needed** — the same 2-node cluster handles base + all addons.
