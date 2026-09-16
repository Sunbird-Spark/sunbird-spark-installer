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

## Deploying Sunbird Spark

Two approaches are available for provisioning infrastructure and deploying Sunbird Spark on Azure — both covered in the setup guide:

**[private-repo-setup/README.md](private-repo-setup/README.md)**

| Approach | When to use |
|----------|-------------|
| **GitHub Actions** | Automated, audit-trailed deployments. Requires a private GitHub repository with Ansible Vault encrypted config and Azure OIDC authentication. |
| **Manual via Azure VM** | Simpler setup with no CI/CD configuration. Create a VM using `setup-installer-vm.sh`, SSH in, and run `install.sh` directly. |

---

## Private AKS Cluster & VPN Access (Azure)

By default the installer creates a **private AKS cluster** — the Kubernetes API server has no public endpoint. Developers and CI/CD runners must be inside the VNet to run `kubectl` or `helm`.

Two independent fields in `global-values.yaml` — `private_cluster_enabled` and `vpn_enabled` — control this and the developer access method (Pritunl VPN vs. Azure Bastion). Full explanation, decision tree, and setup guides:

**[opentofu/azure/README.md](opentofu/azure/README.md#private-cluster--access-options)**

---

## Pre-requisites

1. **Domain Name**
2. **SSL Certificate**: The FullChain, consisting of the private key and Certificate+CA_Bundle, is mandatory for installation.
3. **Google OAuth Credentials**: [Create credentials](https://developers.google.com/workspace/guides/create-credentials#oauth-client-id)
4. **Google V3 ReCaptcha Credentials**: [Create credentials](https://www.google.com/recaptcha/admin)
5. **Email Service Provider**: Only **SendGrid** is supported in this installer. Use your SendGrid API key as the SMTP password.
6. **MSG91 SMS Service Provider API Token** (Optional): Required for sending OTPs during user registration or password reset. Only **MSG91** is supported in this installer.
7. **YouTube API Token** (Optional): Necessary for uploading video content directly via YouTube URL.

> **Note:** This one-click installer supports **SendGrid** for email and **MSG91** for SMS out of the box. Other providers are not supported without customisation.

---

## Required CLI Tools

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

### CLI Versions

The installer has been verified with:

- **OpenTofu**: v1.11.4
- **Terragrunt**: v0.77.5

---

## Installing Sunbird on AWS or GCP

### Notes
- Existing files in the following locations will be backed up with a `.bak` extension and overwritten:
    - `~/.config/rclone/rclone.conf`
    - `~/.kube/config`
- `demo` is used as the environment name below. Replace it with your own (`dev`, `stage`, etc.).

### Steps

1. Clone the repository:
     ```bash
     git clone https://github.com/Sunbird-Spark/sunbird-spark-installer.git
     ```
2. Copy the template directory:
     ```bash
     cd opentofu/<cloud-provider>   # aws or gcp
     cp -r template demo
     cd demo
     ```
3. Fill in the variables in `global-values.yaml`.

4. To enable DIAL addon integration, set `deployed_dial_addon: true` in `global-values.yaml`.

5. To enable asset enrichment, deploy the addon then flip the flag and redeploy knowledgebb:
    ```bash
    # Step 1 — deploy the Flink job
    export ENV_NAME=<env-name>
    cd addons/asset-enrichment/script
    ./addon.sh install azure   # or gcp

    # Step 2 — enable in global-values.yaml
    # set:  enable_asset_enrichment: "true"

    # Step 3 — redeploy knowledgebb to activate the flag in knowlg-service
    cd opentofu/azure/<env-name>
    ./install.sh install_component knowledgebb
    ```

6. Log in to your cloud provider:
    ```bash
    # AWS
    aws configure

    # GCP
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

## SSL Certificate Setup and Renewal

### 1. Automated issuance and renewal (cert-manager)

To have SSL certificates issued and renewed automatically, enable these flags in your
`global-values.yaml`:

```yaml
cert-manager:
  enabled: true
ingress-nginx:
  enabled: true
global:
  cert_manager_ssl: true
  cert_notifications:
    email: "<your-email>" # used for renewal/expiry notices
```

That's it — first-ever issuance and all future renewals happen automatically, with no manual
steps and nothing to paste into `global-values.yaml`.

---

### 2. If you are using a custom certificate

If you already have a custom certificate, leave the flags above set to `false` (or unset), and
provide the private key and the full chain (the certificate concatenated with the CA bundle)
instead. Both are mandatory. Renewal is not automated on this path — you will need to replace
them manually when the certificate expires:

```yaml
global:
  proxy_certificate: |
    -----BEGIN CERTIFICATE-----
    ...your certificate + CA bundle (full chain)...
    -----END CERTIFICATE-----
  proxy_private_key: |
    -----BEGIN PRIVATE KEY-----
    ...your private key...
    -----END PRIVATE KEY-----
```

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

## AKS Kubernetes Version & Upgrade

For instructions on pinning the Kubernetes version, checking available versions, planning an upgrade path, and running the upgrade step-by-step, see:

**[opentofu/azure/README.md — AKS Kubernetes Version](opentofu/azure/README.md#aks-kubernetes-version)**

---

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

## Sync Tool — JanusGraph to OpenSearch

Bulk sync/repair tool for syncing JanusGraph graph data to the OpenSearch composite search index. Runs as a K8s Job — starts, syncs, exits. Zero cost when idle.

Sync tool is a subchart of `knowledgebb`, disabled by default. Controlled via `global-values.yaml`.

### Usage

1. Edit `global-values.yaml` — set sync-tool config:
   ```yaml
   sync-tool:
     enabled: true
     syncMode: full              # full | objectType | identifiers | days | file
     objectType: ""              # e.g. "Content" (when syncMode=objectType)
     identifiers: ""             # e.g. "do_123,do_456" (when syncMode=identifiers)
     days: ""                    # e.g. "5" (when syncMode=days)
   ```

2. Deploy sync-tool only (does not redeploy other knowledgebb charts):
   ```bash
   cd opentofu/<cloud-provider>/<env>
   ./install.sh install_service knowledgebb sync-tool
   ```

3. Monitor logs:
   ```bash
   kubectl logs -f -l app=sync-tool -n sunbird
   ```

4. After sync completes, set `enabled: false` in `global-values.yaml`.

### File Mode

For syncing specific identifiers from a CSV file:

1. Edit `helmcharts/knowledgebb/charts/sync-tool/identifiers.csv` — add one identifier per line
2. Set `syncMode: file` in `global-values.yaml`
3. Deploy: `./install.sh install_service knowledgebb sync-tool`

### GitHub Actions

Check `knowledgebb` bundle + type `sync-tool` in `specific_charts`. Sync config must be set in `global-values.yaml` before triggering.

### When to use

| Scenario | syncMode | value |
|----------|----------|-------|
| Empty index after environment setup | `full` | — |
| Missed CDC events for specific nodes | `identifiers` | `do_123,do_456` |
| Backfill after adding new searchable fields | `full` | — |
| Repair a specific content type | `objectType` | `Content` |
| Catch up after pipeline downtime | `days` | `3` |

---
