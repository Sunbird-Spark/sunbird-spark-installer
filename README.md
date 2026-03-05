# sunbird-spark-installer

Minimum resources required to install and run Sunbird-ED on any cloud provider

| Resource | Node Capacity | Workload Request | Workload Limit | Disk |
|----------|--------------|-----------------|----------------|------|
| **CPU** | 32 vCPU (2 nodes × 16) | ~20 cores | ~46 cores | — |
| **Memory** | 128 GB (2 nodes × 64 GB) | ~40 Gi | ~75 Gi | — |
| **Disk** | — | — | — | ~249 Gi |

> See [Infrastructure Details](#infrastructure-details) for per-component breakdown.

## Infrastructure Details

### Node Configuration

| Cloud Provider | Node Count | VM / Machine Type | vCPU per Node | RAM per Node | Total vCPU | Total RAM |
|----------------|-----------|-------------------|---------------|--------------|------------|-----------|
| **Azure (AKS)** | 2 | Standard_B16as_v2 | 16 | 64 GB | 32 | 128 GB |

---

### Databases

All databases run as Kubernetes workloads inside the cluster.

#### YugabyteDB

YugabyteDB is the primary distributed database used across all building blocks, deployed as **6 pods** (3 masters + 3 tservers).

| Component | Pods | CPU req / limit | Memory req / limit | Disk per pod |
|-----------|------|-----------------|--------------------|--------------|
| Master | 3 | 2 / 2 | 2 Gi / 2 Gi | 25 Gi |
| TServer | 3 | 2 / 2 | 4 Gi / 4 Gi | 25 Gi |

| Port | Usage |
|------|-------|
| 9042 | CQL (Cassandra-compatible) |
| 5433 | PostgreSQL-compatible (YSQL) |

**Databases provisioned per building block:**

| Building Block | Databases |
|----------------|-----------|
| EdBB | kong, druid_raw, superset, registry, portal |
| LearnBB | keycloak, quartz, enc-keys, registry |
| ObsrvBB | superset |
| KnowledgeBB | hierarchy_store, content_store (CQL keyspaces) |

#### Kafka

Runs in KRaft mode. **3 controller pods** (each acts as broker + controller).

| Parameter | Value |
|-----------|-------|
| Pods | 3 (controllers) |
| CPU request / limit | 750m / 1 |
| Memory request / limit | 1024 Mi / 2048 Mi |
| Disk per pod | 8 Gi |
| Port | 9092 |

#### Redis

Runs as a single master. **2 pods** (1 master + 1 replica).

| Component | CPU req / limit | Memory req / limit | Disk |
|-----------|-----------------|--------------------|------|
| Master | 0.5 / 0.5 | 1 Gi / 2 Gi | 25 Gi |
| Replica | 0.5 / 0.5 | 1 Gi / 2 Gi | 25 Gi |

Port: **6379**

#### Elasticsearch

Used by KnowledgeBB and LearnBB.

| Parameter | Value |
|-----------|-------|
| Pods | 1 master (no dedicated data/coordinating replicas) |
| CPU request / limit | 1 / 2 |
| Memory request / limit | 2 Gi / 4 Gi |
| JVM Heap | 2 G |
| Disk | 25 Gi |
| Port | 9200 |

#### JanusGraph

Used by KnowledgeBB. Storage backend is YugabyteDB (CQL) — no local disk.

| Parameter | Value |
|-----------|-------|
| Pods | 1 |
| CPU request / limit | 1 / 3 |
| Memory request / limit | 3 Gi / 6 Gi |
| Persistence | None (uses external YugabyteDB) |
| Port | 8182 |

---

### Flink Jobs

Each Flink job runs with a **JobManager** pod and a **TaskManager** pod.

**Common resource configuration per job (from global-resources.yaml):**

| Parameter | Value |
|-----------|-------|
| CPU request / limit | 100m / 1 |
| Memory request / limit | 1024 Mi / 2048 Mi |
| JobManager heap | 1024 m |
| JobManager process size | 1600 m |
| TaskManager heap | 1024 m |
| TaskManager process size | 1700 m |
| TaskManager replicas | 1 |

#### KnowledgeBB Flink Jobs

| Job | Enabled | Description |
|-----|---------|-------------|
| `transaction-event-processor` | Yes | Processes learning graph events, generates audit telemetry and composite search index |
| `knowlg-publish` | Yes | Handles content/collection publish pipeline |
| `asset-enrichment` | No (disabled by default) | Video/image enrichment; enable via `enable_asset_enrichment: true` |

#### LearnBB Flink Jobs

| Job | Enabled | Description |
|-----|---------|-------------|
| `collection-certificate-generator` | Yes | Generates course completion certificates |
| `notification-job` | Yes | Sends FCM / SMS / email notifications |
| `user-deletion-cleanup` | Yes | Cleans up user data on account deletion |

---

### Application Services

All services run with **1 replica** by default. Resources are sourced from [helmcharts/global-resources.yaml](helmcharts/global-resources.yaml).

#### EdBB

| Service | CPU req / limit | Memory req / limit |
|---------|-----------------|-------------------|
| knowledge-mw | 100m / 1 | 100 Mi / 1 G |
| player (portal) | 100m / 1 | 100 Mi / 1 G |
| kong (API gateway) | 100m / 1 | 100 M / 1 G |
| nginx-public-ingress | 100m / 1 | 100 Mi / 1 G |

#### KnowledgeBB

| Service | CPU req / limit | Memory req / limit |
|---------|-----------------|-------------------|
| knowlg-service | 100m / 1 | 100 Mi / 1024 Mi |
| search-service | 100m / 1 | 100 Mi / 1024 Mi |

#### LearnBB

| Service | CPU req / limit | Memory req / limit |
|---------|-----------------|-------------------|
| lern-service | 100m / 1 | 100 Mi / 2 Gi |
| keycloak | — (no limits set) | — |
| adminutil | 100m / 1 | 100 M / 1 G |
| cert-service | 100m / 1 | 100 Mi / 1024 Mi |
| cert-registry | 100m / 1 | 100 Mi / 1024 Mi |
| certificateapi | 100m / 1 | 100 Mi / 1024 Mi |
| certificatesign | 100m / 1 | 100 Mi / 1024 Mi |
| registry (Sunbird-RC) | 100m / 1 | 100 Mi / 2 G |

#### ObsrvBB

| Service | CPU req / limit | Memory req / limit |
|---------|-----------------|-------------------|
| telemetry-service | 100m / 1 | 100 Mi / 1024 Mi |
| superset | 250m / 512m | 512 Mi / 1024 Mi |

---

### Total Resource Summary

| Category | CPU Request | CPU Limit | Memory Request | Memory Limit | Disk |
|----------|-------------|-----------|----------------|--------------|------|
| Databases | ~17 cores | ~21 cores | ~28 Gi | ~38 Gi | ~249 Gi |
| Flink Jobs (5 enabled) | ~1 core | ~10 cores | ~10 Gi | ~20 Gi | — |
| Application Services | ~2 cores | ~15 cores | ~2 Gi | ~17 Gi | — |
| **Grand Total** | **~20 cores** | **~46 cores** | **~40 Gi** | **~75 Gi** | **~249 Gi** |

**Disk breakdown:**
- YugabyteDB: 6 pods × 25 Gi = 150 Gi
- Kafka: 3 pods × 8 Gi = 24 Gi
- Redis: 2 pods × 25 Gi = 50 Gi
- Elasticsearch: 1 pod × 25 Gi = 25 Gi
- **Total disk: ~249 Gi**

---

## Optional Addons

The following addons can be installed on top of the base platform. Each addon adds additional pods and resource consumption.

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

Flink job that converts uploaded videos to HLS streaming format via Azure Media Services or AWS Elemental MediaConvert.

| Component | Pods | CPU req / limit | Memory req / limit |
|-----------|------|-----------------|--------------------|
| video-stream-generator (Flink JM + TM) | 2 | 100m / 1 each | 500 Mi / 2048 Mi each |
| **Video Stream Total** | **2** | **~0.2 cores / ~2 cores** | **~1 Gi / ~4 Gi** |

### Total Resource Summary with All Addons

| Category | CPU Request | CPU Limit | Memory Request | Memory Limit | Disk |
|----------|-------------|-----------|----------------|--------------|------|
| Base Platform | ~20 cores | ~46 cores | ~40 Gi | ~75 Gi | ~249 Gi |
| DIAL Addon | ~0.5 cores | ~5 cores | ~2 Gi | ~9 Gi | — |
| Discussion Forum Addon | ~0.3 cores | ~3 cores | ~0.3 Gi | ~4 Gi | — |
| Video Stream Generator Addon | ~0.2 cores | ~2 cores | ~1 Gi | ~4 Gi | — |
| **Grand Total (all addons)** | **~21 cores** | **~56 cores** | **~43 Gi** | **~92 Gi** | **~249 Gi** |

> **In general:** All addons together add only ~1 CPU core and ~3 Gi of memory requests on top of the base platform. **No additional nodes are needed** — the same 2-node cluster (32 vCPU / 128 GB RAM) comfortably fits the base platform plus all addons.

---

## Installing Sunbird on Any Cloud Provider

### Pre-requisites

1. **Domain Name**
2. **SSL Certificate**: The FullChain, consisting of the private key and Certificate+CA_Bundle, is mandatory for installation.
3. **Google OAuth Credentials**: [Create credentials](https://developers.google.com/workspace/guides/create-credentials#oauth-client-id)
4. **Google V3 ReCaptcha Credentials**: [Create credentials](https://www.google.com/recaptcha/admin)
5. **Email Service Provider**
6. **MSG91 SMS Service Provider API Token** (Optional): Required for sending OTPs to registered email addresses during user registration or password reset.
7. **YouTube API Token** (Optional): Necessary for uploading video content directly via YouTube URL.

### Required CLI Tools
1. [jq](https://jqlang.github.io/jq/download/)
2. [yq](https://github.com/mikefarah/yq#install) (for YAML processing)
3. [rclone](https://rclone.org/)
4. [OpenTofu](https://opentofu.org/docs/intro/install/)
5. [Terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/)
6. Linux / MacOS / GitBash (Windows)
7. Python 3 
8. PyJWT Python Package (install via pip)
9. [kubectl](https://kubernetes.io/docs/tasks/tools/)
10. [helm](https://helm.sh/docs/intro/quickstart/#install-helm)
11. [Postman CLI](https://learning.postman.com/docs/getting-started/installation/installation-and-updates/)
12. For cloud-specific tools, follow the instructions in the respective README file based on your provider.  
    Example for Azure: [opentofu/azure/README.md](opentofu/azure/README.md)

### CLI Versions

The installer has been used and verified with the following CLI versions:

- **OpenTofu**: v1.11.4
- **Terragrunt**: v0.77.5

While the installer may work with other versions, these are the versions that have been tested and confirmed to work. If you encounter issues with different versions, please try using these specific versions.
### Notes
- Existing files in the following locations will be backed up with a `.bak` extension, and the files will be overwritten:
    - `~/.config/rclone/rclone.conf`
    - `~/.kube/config`
- In the instructions below, `demo` is used as the environment name. You can replace it with your desired environment name, such as `dev`, `stage`, etc.

### Steps to Clone and Prepare

1. Clone the repository:a
     ```bash
     git clone https://github.com/project-sunbird/sunbird-ed-installer.git
     ```
2. Copy the template directory:
     ```bash
     cd opentofu/<cloud-provider>   # Replace <cloud-provider> with your cloud provider (e.g., azure, aws, gcp)
     cp -r template demo
     cd demo
     ```
3. Fill in the variables in `demo/global-values.yaml`.
   take reference from  [opentofu/azure/README.md]

4. Enabling DIAL Addon Integration

     The DIAL addon is deployed independently via the scripts in `addons/dial`. However, the core Sunbird services (LMS, Player, etc.) need to be aware of the DIAL addon to enable proper integration and routing.

     - **To Enable Integration**: Set `deployed_dial_addon: true` in your `global-values.yaml` file. This tells the core installation script to include addon-specific configurations.
     
     - **When to set this**: Enable this flag if you have deployed or intend to deploy the DIAL addon.

     Example in `global-values.yaml`:

     ```yaml
     deployed_dial_addon: true
     ```

5. Enabling Asset Enrichment

     If you want to enable asset enrichment, you can control it using the
     `enable_asset_enrichment` flag.

     - Default: `false` (Asset enrichment is disabled)

     - To enable: set it to `true` in your `global-values.yaml` file. For example:

         ```yaml
         enable_asset_enrichment: true
         ```

6. Log in to your cloud provider:
    ```bash
    # If  cloud provider is Azure
    az login --tenant AZURE_TENANT_ID

    # If cloud provider is AWS
    aws configure

    # If cloud provider is GCP
    gcloud auth login
    ```
7. Run the installation script:
     ```bash
     time ./install.sh
     ```

## Default Users in the Instance

This installation setup creates the following default users with different roles. You can update the passwords using the "Forgot Password" option or create new users using APIs.

| Role              | Email/User Name           | Password         |
|-------------------|---------------------------|------------------|
| Admin             | admin@yopmail.com         | Admin@123        |
| Content Creator   | contentcreator@yopmail.com| Creator@123      |
| Content Reviewer  | contentreviewer@yopmail.com | Reviewer@123   |
| Book Creator      | bookcreator@yopmail.com   | Bookcreator@123  |
| Book Reviewer     | bookreviewer@yopmail.com  | bookReviewer@123 |
| Public User 1     | user1@yopmail.com         | User1@123        |
| Public User 2     | user2@yopmail.com         | User2@123        |


##  Destorying the sunbird instance
```bash
cd opentofu/<cloud-provider>/<env>
time ./install.sh destroy_tf_resources
```

## Note:

## SSL Certificate Setup and Renewal (Let’s Encrypt Integration)

If you are using Let’s Encrypt for SSL certificate management, follow the steps below to ensure proper setup and renewal handling.

---

### 1. Enable Let’s Encrypt in Nginx

In your `global-values.yaml`, set the following flag:

```yaml
lets_encrypt_ssl: true
```

This enables automatic SSL certificate issuance and renewal via a Kubernetes Certbot CronJob.

---

### 2. Automatic Certificate Renewal

When `lets_encrypt_ssl` is enabled:

- The Certbot CronJob automatically renews your SSL certificates approximately every **85 days**.
- After renewal, it updates the SSL certificate and private key in the Kubernetes ConfigMap named `nginx-public-ingress`.

---

### 3. Update Global Values After Renewal

Once the renewal completes:

1. Fetch the renewed keys from the ConfigMap.
2. Update your `opentofu/<cloud-provider>/<env>/global-values.yaml` file with the new values:

```yaml
proxy_private_key: |
  <paste the renewed private key from ConfigMap>

proxy_certificate: |
  <paste the renewed certificate from ConfigMap>
```

These values are essential because **edbb bundle  fetches SSL certificates from the global level** defined in above file.

---

### 4. If Not Using Let’s Encrypt

If you are not using Let’s Encrypt:
x
- Keep `lets_encrypt_ssl: false`.
- Manually provide your SSL certificate and private key under the same fields in `global-values.yaml`.

---
### Additional Notes
- The CronJob handles only Let’s Encrypt–issued certificates.
- The default renewal schedule is every **85 days**.
- Always ensure your domain DNS records are properly configured and reachable before renewal.

# Grafana Alloy Helm Chart

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm search repo grafana/alloy
helm pull grafana/alloy
```

This will download the Helm chart as a `.tgz` file.

## Installation Steps

1. Extract the downloaded `.tgz` file.
2. Replace the extracted folder in the following directory:

```text
sunbird-ed-installer/helmcharts/monitoring/charts/alloy
```

3. Update the image version in the following file to match the latest version available in the Grafana Alloy Helm chart:

```text
sunbird-ed-installer/helmcharts/images.yaml
```

# JanusGraph Helm Chart

**Current JanusGraph Base Image Version**: bitnami/janusgraph:1.1.0

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo bitnami/janusgraph
helm pull bitnami/janusgraph
```

This will download the Helm chart as a `.tgz` file.

## Installation Steps

1. Extract the downloaded `.tgz` file.
2. Replace the extracted folder in the following directory:

```text
sunbird-ed-installer/helmcharts/edbb/charts/janusgraph
```

3. Update the JanusGraph version in the configuration files to match the version being used.

## Kong Upgrade Guide

This section documents the Kong API Gateway upgrade process from version 0.14.1 to 3.9.1 and provides instructions for future upgrades.

### Current Kong Version

- **Kong**: 3.9.1
- **Kong Scripts Image**: `sunbirded.azurecr.io/kong-scripts:3.9.1`

### Building Kong Scripts Image

The `kong-scripts` image is used for `kong-apis` and `kong-consumers` jobs. To build and push a new version:

```bash
cd scripts/kong-api-scripts

# Build for AMD64 architecture (recommended for Azure/AWS/GCP)
docker buildx build --platform linux/amd64 -t <registry>/kong-scripts:3.9.1 --push .

# Build for multiple architectures
docker buildx build --platform linux/amd64,linux/arm64 -t <registry>/kong-scripts:3.9.1 --push .
```

**Important**: Always build for `linux/amd64` for production environments running on Azure, AWS, or GCP to avoid "exec format error" issues.

### Kong Upgrade Process (0.14.1 → 3.9.1)

#### 1. Database Compatibility

Kong 3.9.1 requires PostgreSQL-compatible databases. When using YugabyteDB:

- Use the PostgreSQL port (default: `5433`)
- Expect slower migration performance compared to native PostgreSQL (10-20x slower)
- Increase migration timeouts significantly

#### 2. Migration Job Configuration

The Kong migration job has been enhanced with extended timeout settings for YugabyteDB compatibility:

```yaml
env:
  - name: KONG_PG_CONNECT_TIMEOUT
    value: "600"  # 10 minutes
  - name: KONG_PG_STATEMENT_TIMEOUT
    value: "600000"  # 10 minutes (in milliseconds)
  - name: KONG_PG_IDLE_IN_TRANSACTION_SESSION_TIMEOUT
    value: "120000"  # 2 minutes (in milliseconds)
  - name: KONG_PG_KEEPALIVE_TIMEOUT
    value: "600"  # 10 minutes
```

#### 3. JWT Plugin Changes

Kong 3.9.1 changed the JWT credential storage format:

- **Old (0.14.1)**: Stored `iss` field separately
- **New (3.9.1)**: Only stores `key` field (equivalent to `iss`)

**Fix Applied**: Updated `kong_consumers.py` at line 127:

```python
# OLD: if saved_credential.get('iss') == credential_iss:
# NEW:
if saved_credential.get('key') == credential_iss:
```

### References

- [Kong Migration Guide](https://docs.konghq.com/gateway/latest/upgrade/)
- [Kong 3.9.x Release Notes](https://docs.konghq.com/gateway/changelog/)
- [YugabyteDB PostgreSQL Compatibility](https://docs.yugabyte.com/preview/explore/ysql-language-features/)

---

