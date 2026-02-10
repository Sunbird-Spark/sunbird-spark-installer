# DIAL Service Addon - Quick Start Guide

## Prerequisites

- `helm` 3.x installed
- `kubectl` configured and connected to cluster
- **OpenTofu must be run first** to generate `global-cloud-values.yaml`
  - This file is created in `opentofu/azure/template/` or `opentofu/gcp/template/`
  - It contains all the required configuration values

## Checklist

- [ ] Running Sunbird cluster
- [ ] Azure storage container `dial_state_container_public` exists

## Quick Installation

```bash
cd addons/dial
./script/manage.sh install
```

**That's it!** The script automatically:
- Uses namespace `sunbird`
- Loads all configuration from terraform output
- Uses the `dial_state_container_public` created by opentofu
- Configures all service endpoints

## Verify Installation

```bash
# Check pod status
kubectl get pods -n sunbird -l app.kubernetes.io/name=dial

# Check logs
kubectl logs -n sunbird -l app.kubernetes.io/name=dial -f

# Test health endpoint
kubectl port-forward -n sunbird svc/dial-service 9000:9000
curl http://localhost:9000/health
```

## Uninstallation

```bash
./script/manage.sh uninstall
```
