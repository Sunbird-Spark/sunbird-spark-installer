# DIAL Service Addon

## Overview

The DIAL (Digital Infrastructure for Augmented Learning) Service is a QR code generation and management service for learning content. It provides APIs for creating, linking, and managing DIAL codes that can be used to access educational content.

## Prerequisites

- `helm` 3.x installed
- `kubectl` configured and connected to cluster
- **OpenTofu must be run first** to generate `global-cloud-values.yaml`
  - This file is created in your environment folder: `opentofu/<provider>/<env_name>/`
  - It contains all the required configuration values

## Checklist

- [ ] Running Sunbird cluster with required services
- [ ] OpenTofu has been executed successfully
- [ ] Azure storage container `dial_state_container_public` exists (for Azure deployments)
- [ ] Kafka topics are created (auto-created by knowledgebb chart)


## Quick Installation

```bash
cd addons/dial
export ENV_NAME=demo # Replace with your environment name
./script/manage.sh install
```

**That's it!** The script automatically:
- **Provisions cloud resources** (if `opentofu` directory exists) using Terragrunt
- Uses namespace `sunbird` (default)
- Loads configuration from OpenTofu-generated files
- Merges shared addon values from `addons/global-values.yaml`
- Uses the `dial_state_container_public` created by OpenTofu

### Installation Options

```bash
# Install for a specific cloud provider (defaults to azure)
./script/manage.sh install azure
./script/manage.sh install gcp

# Specify a custom environment directory (e.g., if you copied template to 'demo')
export ENV_NAME=demo
./script/manage.sh install azure

# Uninstall everything
./script/manage.sh uninstall azure
```

## Verify Installation

```bash
# Check pod status
kubectl get pods -n sunbird -l app.kubernetes.io/name=dial

# Check logs
kubectl logs -n sunbird -l app.kubernetes.io/name=dial -f

# Check service
kubectl get svc -n sunbird dial

# Test health endpoint
kubectl port-forward -n sunbird svc/dial 9000:9000
curl http://localhost:9000/health
`````

## Uninstallation

```bash
cd addons/dial
./script/manage.sh uninstall
```
