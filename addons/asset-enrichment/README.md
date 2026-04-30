# Asset Enrichment Addon

## Overview

The Asset Enrichment addon is an Apache Flink job that processes video and image assets published to Kafka. It enriches content metadata by generating thumbnails, extracting video duration, processing YouTube links, and triggering video stream generation for supported MIME types.

## Prerequisites

- `helm` 3.x installed
- `kubectl` configured and connected to cluster
- **OpenTofu must be run first** to generate `global-cloud-values.yaml`
  - This file is created in your environment folder: `opentofu/<provider>/<env_name>/`
  - It contains all the required configuration values

## Checklist

- [ ] Running Sunbird cluster with `knowledgebb` deployed
- [ ] OpenTofu has been executed successfully
- [ ] Kafka topic `<env>.knowlg.learning.job.request` exists (created by `knowledgebb` provisioning)

## Installation

**Step 1 — Deploy the Flink job**

```bash
export ENV_NAME=demo  # Replace with your environment name
cd addons/asset-enrichment/script
./addon.sh install azure   # or gcp
```

**Step 2 — Enable in knowlg-service and redeploy knowledgebb**

In `opentofu/<provider>/<env>/global-values.yaml`, set:
```yaml
enable_asset_enrichment: "true"
```

Then redeploy knowledgebb from your environment folder:
```bash
cd opentofu/azure/<env>
./install.sh install_component knowledgebb
```

This updates the `knowlg-service` config so it starts publishing asset events to the Kafka topic that the Flink job consumes.

## Verify Installation

```bash
# Check pod status
kubectl get pods -n sunbird | grep asset-enrichment

# Check logs - JobManager
kubectl logs -n sunbird -l app.kubernetes.io/component=asset-enrichment-jobmanager -f

# Check logs - TaskManager
kubectl logs -n sunbird -l app.kubernetes.io/component=asset-enrichment-taskmanager -f

# Access Flink UI
kubectl port-forward -n sunbird svc/asset-enrichment-jobmanager 8081:8081
# Open http://localhost:8081 in browser
```

## Uninstallation

```bash
cd addons/asset-enrichment
./script/addon.sh uninstall
```
