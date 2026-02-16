# Discussion Forum Addon

## Overview

The Discussion Forum addon provides a complete discussion and community management solution for Sunbird. It consists of three integrated services:

- **NodeBB**: A modern, feature-rich forum platform that powers the discussion interface
- **Discussion Middleware**: A middleware service that bridges NodeBB with Sunbird's backend services
- **Groups Service**: Manages user groups, group activities, and group-based discussions

## Prerequisites

- `helm` 3.x installed
- `kubectl` configured and connected to cluster
- **OpenTofu must be run first** to generate `global-cloud-values.yaml`
  - This file is created in your environment folder: `opentofu/<provider>/<env_name>/`
  - It contains all the required configuration values
- Running Redis instance (required by NodeBB)
- Running Cassandra/YugabyteDB instance (required by Groups Service)
- Running Kafka instance (required by Groups Service)

## Checklist

- [ ] Running Sunbird cluster with required services (Redis, Cassandra/YugabyteDB, Kafka)
- [ ] OpenTofu has been executed successfully
- [ ] User and notification services are deployed (required by Groups Service)

## Quick Installation

```bash
cd addons/discussion-forum
export ENV_NAME=demo # Replace with your environment name
./scripts/manage.sh install
```

**That's it!** The script automatically:
- Deploys all three services: **discussionmw**, **nodebb**, and **groups**
- Uses namespace `sunbird` (default)
- Loads configuration from OpenTofu-generated files
- Merges shared addon values from `addons/global-values.yaml`
- Applies image configurations from `addons/images.yaml` (via `global.images`)
- Uses resources and service settings from each helmchart's `values.yaml`

### Installation Options

```bash
# Install for a specific cloud provider (defaults to azure)
./scripts/manage.sh install azure
./scripts/manage.sh install gcp

# Specify a custom environment directory (e.g., if you copied template to 'demo')
export ENV_NAME=demo
./scripts/manage.sh install azure

# Uninstall everything
./scripts/manage.sh uninstall azure
```

## Services Deployed

### 1. NodeBB (Port 4567)
- Modern forum platform
- Handles discussion threads, posts, and user interactions
- Requires Redis for session management and caching

### 2. Discussion Middleware (Port 3002)
- Bridges NodeBB with Sunbird backend
- Provides API endpoints for discussion management
- Health check: `/health`

### 3. Groups Service (Port 9000)
- Manages user groups and group activities
- Integrates with user-org and notification services
- Health check: `/service/health`

## Verify Installation

```bash
# Check all discussion forum pods
kubectl get pods -n sunbird | grep -E "discussionmw|nodebb|groups"

# Check specific service status
kubectl get pods -n sunbird -l app.kubernetes.io/name=discussionmw
kubectl get pods -n sunbird -l app.kubernetes.io/name=nodebb
kubectl get pods -n sunbird -l app.kubernetes.io/name=groups

# Check logs - Discussion Middleware
kubectl logs -n sunbird -l app.kubernetes.io/name=discussionmw -f

# Check logs - NodeBB
kubectl logs -n sunbird -l app.kubernetes.io/name=nodebb -f

# Check logs - Groups Service
kubectl logs -n sunbird -l app.kubernetes.io/name=groups -f

# Check service endpoints
kubectl get svc -n sunbird | grep -E "discussionmw|nodebb|groups"

# Port forward to access NodeBB locally
kubectl port-forward -n sunbird svc/nodebb 4567:4567
# Open http://localhost:4567 in browser

# Port forward to access Discussion Middleware
kubectl port-forward -n sunbird svc/discussionmw 3002:3002
# Access http://localhost:3002/health

# Port forward to access Groups Service
kubectl port-forward -n sunbird svc/groups 9000:9000
# Access http://localhost:9000/service/health
```

## Configuration Files

- **`../images.yaml`**: Container image configurations using `global.images` structure (located in addons directory)
  - Images are referenced in deployment templates via `.Values.global.images.discussionmw`, `.Values.global.images.nodebb`, and `.Values.global.images.groups`
  - Follows the same pattern as `dial_service` and `knowledge_platform_jobs`
- **`helmcharts/discussionmw/values.yaml`**: Discussion Middleware configuration (resources, service settings)
- **`helmcharts/nodebb/values.yaml`**: NodeBB configuration (resources, service settings)
- **`helmcharts/groups/values.yaml`**: Groups Service configuration (resources, service settings)

## Troubleshooting

### NodeBB fails to start
- Ensure Redis is running and accessible: `kubectl get pods -n sunbird | grep redis`
- Check NodeBB logs for connection errors
- Verify Redis connection details in the configuration

### Groups Service fails to start
- Ensure Cassandra/YugabyteDB is running
- Verify Kafka is accessible
- Check that userorg-service and notification-service are deployed
- Review Groups Service logs for detailed error messages

### Discussion Middleware health check fails
- Verify the service is running: `kubectl get pods -n sunbird -l app.kubernetes.io/name=discussionmw`
- Check if the health endpoint is responding: `curl http://discussionmw:3002/health`
- Review middleware logs for errors

## Uninstallation

```bash
cd addons/discussion-forum
./scripts/manage.sh uninstall
```

This will remove all three services (discussionmw, nodebb, and groups) from the cluster.
