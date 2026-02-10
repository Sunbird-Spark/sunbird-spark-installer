# Video Stream Generator Addon

## Overview

The Video Stream Generator is an Apache Flink job that handles video transcoding and HLS (HTTP Live Streaming) stream generation. It processes video content published to Kafka and generates adaptive bitrate streams using either Azure Media Services or AWS Elemental MediaConvert.

## Prerequisites

- `helm` 3.x installed
- `kubectl` configured and connected to cluster
- **OpenTofu must be run first** to generate `global-cloud-values.yaml`
  - This file is created in `opentofu/azure/template/` or `opentofu/gcp/template/`
  - It contains all the required configuration values

## Checklist

- [ ] Running Sunbird cluster with required services
- [ ] OpenTofu has been executed successfully

## Quick Installation

```bash
cd addons/video-stream-generator
./script/manage.sh install
```

**That's it!** The script automatically:
- Uses namespace `sunbird` (default)
- Loads configuration from OpenTofu-generated files
- Merges addon-specific values from `global-values.yaml`

### Installation Options

```bash
# Install with custom namespace
./script/manage.sh install -n my-namespace

# Install with custom release name
./script/manage.sh install -r my-vsg-release

# Install with custom values file
./script/manage.sh install -f custom-values.yaml
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
./script/manage.sh uninstall
```
