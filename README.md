# sunbird-spark-installer

Minimum resources required to install and run Sunbird-ED on any cloud provider

## Infrastructure Overview

**Node:** 2 × Azure Standard_B16as_v2 (16 vCPU / 64 GB RAM) → **32 vCPU / 128 GB RAM total**

### What runs in the cluster

| Category | Count |
|----------|-------|
| Databases (YugabyteDB, Redis*, Elasticsearch, JanusGraph) | 4 |
| Flink Jobs (enabled by default) | 5 |
| Application Services  | 14 |
| Monitoring Stack (Grafana, Loki, Prometheus, Grafana Alloy) | 4 |
| Velero (backup & disaster recovery) | 1 |

> *Redis is optional 

### Resources without addons

| Resource | Request | Limit | Disk |
|----------|---------|-------|------|
| CPU | ~21 cores | ~50 cores | — |
| Memory | ~40 Gi | ~74 Gi | — |
| Disk | — | — | ~219 Gi |

### Optional addons

| Addon | What it adds |
|-------|-------------|
| DIAL | 1 service + 2 Flink jobs |
| Discussion Forum | 3 services |
| Video Stream Generator | 1 Flink job |

### Resources with all addons installed

| Resource | Request | Limit | Disk |
|----------|---------|-------|------|
| CPU | ~22 cores | ~60 cores | — |
| Memory | ~43 Gi | ~91 Gi | — |
| Disk | — | — | ~219 Gi |

> No additional nodes needed — the same 2-node cluster handles base + all addons.

> For per-component resource breakdown, see [INFRA_DETAILS.md](INFRA_DETAILS.md).

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
     
     - **When to set this**: Enable this flag and deploy core services, if you have deployed or intend to deploy the DIAL addon.

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

## Data Migration Guide

Steps to migrate data from an existing Sunbird cluster to a new cluster.

### Step 1 — Prepare Old Cluster

Expose these services as **LoadBalancer** in the **old cluster**:

| Service | Port |
|---------|------|
| Cassandra | 9042 |
| PostgreSQL | 5432 |
| Neo4j | 7687 |
| Elasticsearch | 9200 |

```bash
kubectl patch svc <service-name> -n sunbird -p '{"spec": {"type": "LoadBalancer"}}'
```

### Step 2 — Prepare New Cluster Branch

```bash
git checkout develop
git checkout -b release-8.1.0-migration
```

### Step 3 — Deploy Only Databases

On the new cluster, deploy **only** YugabyteDB, JanusGraph, and Elasticsearch first. Wait for all three to be healthy before proceeding.

### Step 4 — Run Data Migration

Update the external IPs in `migration/db-migration/values.yaml` and run each job one at a time in this order:

| Order | Job |
|-------|-----|
| 1 | postgres |
| 2 | keycloak |
| 3 | cassandra |
| 4 | neo4j |
| 5 | elasticsearch |
| 6 | createdat |

Refer to [migration/DB-migration.md](migration/DB-migration.md) for the full migration steps.

### Step 5 — Update Encryption Key

In `helmcharts/learnbb/charts/lern/configs/env.yaml`, update `sunbird_encryption_key` with the value from the **old cluster's** userorg env:

```yaml
sunbird_encryption_key: "<value from old cluster userorg env>"
```

### Step 6 — Deploy All Bundles

```bash
bash install.sh install_helm_components
```

### Step 7 — DNS Mapping

```bash
kubectl get svc nginx-public-ingress -n sunbird -ojsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Point your domain DNS A record to the above IP and wait for propagation.

### Step 8 — Generate Postman Environment

```bash
bash install.sh generate_postman_env
```

### Step 9 — Run Spark Forms

```bash
bash install.sh create_client_forms
```

