# Video Stream Generator Addon

## Overview

The Video Stream Generator is an Apache Flink job that handles video transcoding and HLS (HTTP Live Streaming) stream generation. It processes video content published to Kafka and generates adaptive bitrate streams using either Azure Media Services or AWS Elemental MediaConvert.

## Prerequisites

- `helm` 3.x installed
- `kubectl` configured and connected to cluster
- **OpenTofu must be run first** to generate `global-cloud-values.yaml`
  - This file is created in your environment folder: `opentofu/<provider>/<env_name>/`
  - It contains all the required configuration values

## Checklist

- [ ] Running Sunbird cluster with required services
- [ ] OpenTofu has been executed successfully

## Quick Installation

```bash
cd addons/video-stream-generator
export ENV_NAME=demo # Replace with your environment name
./script/addon.sh install
```

**That's it!** The script automatically:
- **Provisions cloud resources** (if `opentofu` directory exists) using Terragrunt
- Uses namespace `sunbird` (default)
- Loads configuration from OpenTofu-generated files
- Merges shared addon values from `addons/global-values.yaml`

### Installation Options

```bash
# Install for a specific cloud provider (defaults to azure)
./script/addon.sh install azure
./script/addon.sh install gcp

# Specify a custom environment directory (e.g., if you copied template to 'demo')
export ENV_NAME=demo
./script/addon.sh install azure

# Uninstall everything
./script/addon.sh uninstall azure
```

## Verify Installation

```bash
# Check pod status
kubectl get pods -n sunbird -l app.kubernetes.io/name=video-stream-generator

# Check JobManager and TaskManager
kubectl get pods -n sunbird | grep video-stream-generator

# Check logs - JobManager
kubectl logs -n sunbird -l app.kubernetes.io/component=video-stream-generator-jobmanager -f

# Check logs - TaskManager
kubectl logs -n sunbird -l app.kubernetes.io/component=video-stream-generator-taskmanager -f

# Access Flink UI
kubectl port-forward -n sunbird svc/video-stream-generator-jobmanager 8081:8081
# Open http://localhost:8081 in browser
```

## Uninstallation

```bash
cd addons/video-stream-generator
./script/addon.sh uninstall
```
