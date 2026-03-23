# Obsrv Add-on Setup

## Prerequisites

Clone the obsrv-automation repo into this folder and checkout the latest release tag:

```bash
cd addons/obsrv
git clone https://github.com/Sanketika-Obsrv/obsrv-automation.git .
git tag --sort=-v:refname | head -5   # list latest tags
git checkout <latest-tag>             # e.g. git checkout v1.2.0
```

## Required File Changes

After cloning, make the following changes before running `install.sh`:

### 1. `helmcharts/kitchen/install.sh`

- Comment out the `kafka40)` section — Kafka already runs in the sunbird namespace
- Comment out the `kafka40` call inside `core-setup)`

### 2. `helmcharts/global-values.yaml`

| Field | Line | Value |
|-------|------|-------|
| `grafana_admin_password` | ~62 | Set your Grafana admin password (from sunbird monitoring stack) |
| `grafana_url` | ~63 | `http://monitoring-grafana.sunbird.svc.cluster.local` |
| `domain` | ~107 | Set to your IP/domain (e.g. `<IP>.sslip.io`) |
| `kafka.host` | ~120 | `kafka.sunbird.svc.cluster.local` |
| `kafka.bootstrap-server` | ~122 | `kafka.sunbird.svc.cluster.local:9092` |
| `kafka40.host` | ~174 | `kafka.sunbird.svc.cluster.local` |
| `kafka40.bootstrap-server` | ~179 | `kafka.sunbird.svc.cluster.local:9092` |

### 3. Cloud-specific values file

Update the file based on your cloud provider:

| Cloud Provider | File to update | `cloud_env` value |
|----------------|----------------|-------------------|
| Azure | `helmcharts/global-cloud-values-azure.yaml` | `azure` |
| AWS | `helmcharts/global-cloud-values-aws.yaml` | `aws` |
| GCP | `helmcharts/global-cloud-values-gcp.yaml` | `gcp` |

#### Azure (`helmcharts/global-cloud-values-azure.yaml`)

| Field | Value |
|-------|-------|
| `ssl_enabled` | `true` or `false` based on your setup (see Kong section below) |
| `cloud_storage_region` | Your Azure region |
| `azure_storage_account_name` | Your storage account name |
| `azure_storage_account_key` | Your storage account key |
| `container` | Your container name (same for all container fields) |
| `storage_class_name` | `default` |
| `azure_resource_group` | Your resource group |
| `azure_subscription_id` | Your subscription ID |
| `azure_tenant_id` | Your tenant ID |
| `checkpoint_bucket` | `wasbs://<container>@<storage-account>.blob.core.windows.net/flink-checkpoints` |
| `cloud_storage_config` | `'{"identity":"<storage-account>","credential":"<storage-key>","region":"<region>"}'` |

#### AWS (`helmcharts/global-cloud-values-aws.yaml`)

Fill in your AWS-specific values: S3 bucket, region, access keys, etc.

#### GCP (`helmcharts/global-cloud-values-gcp.yaml`)

Fill in your GCP-specific values: GCS bucket, project, region, service account, etc.

#### Kong configuration (depends on `ssl_enabled`)

- **If `ssl_enabled: false`** — Keep Kong as `NodePort` (default). The node IP must be public with an external IP. No annotations needed.
  ```yaml
  kong:
    proxy:
      annotations: {}
      type: NodePort
  ```

- **If `ssl_enabled: true`** — Change Kong to `LoadBalancer` and add cloud-specific LB annotations. For Azure:
  ```yaml
  kong_annotations: &kong_annotations
    service.beta.kubernetes.io/azure-load-balancer-internal: "false"
    service.beta.kubernetes.io/azure-pip-name: "<your-public-ip-name>"
    service.beta.kubernetes.io/azure-load-balancer-resource-group: "MC_<resource-group>_<cluster-name>_<region>"

  kong:
    proxy:
      annotations: *kong_annotations
      type: LoadBalancer
  ```

### 4. `helmcharts/services/dataset-api/values.yaml`

Update Grafana URL in two places (~line 185-186):
```yaml
grafana_url: "http://monitoring-grafana.sunbird.svc.cluster.local"
GRAFANA_ADMIN_URL: http://monitoring-grafana.sunbird.svc.cluster.local
```

## Installation

After making all the file changes above, run the following commands:

```bash
cd helmcharts/kitchen

# Set cloud environment (azure, aws, or gcp)
export cloud_env=azure

# Step 1: Install core setup (bootstrap, prerequisites, coredb)
# Note: kafka40 is skipped — already running in sunbird namespace
bash install.sh core-setup

# Step 2: Install all remaining components (migrations, monitoring, oauth, coreinfra, obsrvapis, obsrvtools, additional)
bash install.sh all
```

### What each step installs

**`core-setup`** runs in order:
1. `bootstrap` — Obsrv bootstrapper (namespace, secrets, etc.)
2. `prerequisites` — Prerequisites (minio for non-cloud setups)
3. `coredb` — PostgreSQL, Kong, Druid operator, Valkey, cert-manager (if SSL enabled)

**`all`** runs in order:
1. `migrations` — PostgreSQL migrations, Kubernetes reflector, Grafana configs, LetsEncrypt SSL
2. `monitoring` — Prometheus pushgateway, Kafka exporter, alert rules (does NOT install Grafana or Prometheus — uses sunbird's existing monitoring stack)
3. `oauth` — Keycloak
4. `coreinfra` — Druid, Flink, Superset
5. `obsrvapis` — Command API, Dataset API
6. `obsrvtools` — Web console, Submit ingestion
7. `additional` — Spark, Secor, Druid exporter, PostgreSQL exporter/backup, Kong ingress routes, etc.

## Notes

- The `monitoring)` step only installs prometheus-pushgateway, kafka-exporter, and alert-rules. It does NOT install Grafana or Prometheus — those are already running in sunbird's monitoring stack.
- Kafka is shared from the sunbird namespace, so `kafka40` installation is skipped.
- You can also install individual services: `bash install.sh <service-name>` (e.g. `bash install.sh dataset-api`)
