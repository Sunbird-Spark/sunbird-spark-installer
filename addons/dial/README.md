# DIAL Service Addon

## Overview

The DIAL (Digital Infrastructure for Augmented Learning) Service is a QR code generation and management service. It provides APIs for creating, linking, and managing DIAL codes.

This addon includes:
1. **DIAL Service**: The core Play/Pekko application.
2. **DIAL Code Context Updater**: A Flink job for real-time DIAL code metadata updates.
3. **Cloud Infrastructure**: Automated provisioning of required Azure storage containers.
4. **Ingress Routing**: Dynamic routing injection into the core Nginx Ingress controllers.

## Prerequisites

- `helm` 3.x and `terragunt` installed
- `yq` installed (for automated value injection)
- `kubectl` configured and connected to cluster
- **Core OpenTofu must be run first** to generate standard `global-cloud-values.yaml` in `opentofu/azure/<env_name>/`.

## Installation

The installation follows a two-step process: **Provisioning** and **Deployment**.

### 1. Simple Installation (Automatic)
The `addon.sh` script manages the lifecycle. Note that for safety, **cloud provisioning is disabled by default** in the script.

```bash
export ENV_NAME=dev  # Replace with your environment name (e.g., dev, demo)
cd addons/dial
./script/addon.sh install azure
```

**What the script does (when fully enabled):**
1. **Provision Resources**: Runs Terragrunt in `addons/dial/opentofu/azure/storage` to create a dedicated DIAL storage container. *(To enable this, uncomment `provision_resources` in the `install()` function of `addon.sh`)*.
2. **Inject Values**: Automatically updates `addons/global-values.yaml` with the name of the newly created container.
3. **Deploy Charts**: Installs the `dial` and `dialcode-context-updater` Helm charts.
4. **Inject Routing**: Creates ConfigMaps that the core Gateways (Public/Private) use to route `/dial/` traffic.

---

## Infrastructure Management

### Storage Container Creation
The storage container is managed separately from the core infrastructure for safety. 
- **Naming Convention**: `ed-<env>-dial-<random>` (e.g., `ed-devl-dial-xjvuuo8x`).
- **State File**: Stored in `addons/dial/opentofu/azure/storage/tofu.tfstate`.
- **Safety**: The addon "reads" the main storage account via data sources and never attempts to modify the root account.

### Verifying Before Actions
The `provision_resources` and `destroy_resources` functions are designed to show you a **Plan** before they perform any actions.
- **To Plan/Provision**: uncomment `provision_resources` in `install()`.
- **To Plan/Destroy**: uncomment `destroy_resources` in `uninstall()`.
- **Verification**: If you want to *only* plan without applying, comment out the `apply` or `destroy` lines inside those specific functions in `addon.sh`.

---

## Technical Details

### Database Compatibility (YugabyteDB)
The DIAL service uses the Datastax Cassandra driver. To ensure compatibility with YugabyteDB's system tables, the following JVM flags are automatically applied:
- `-Dcassandra.metadata.enabled=false`
- `-Dcassandra.metadata_enabled=false`

### Ingress Decoupling
DIAL uses a "drop-in" pattern for Nginx. Instead of modifying the core gateway:
1. The addon chart creates `dial-public-nginx-config` (ConfigMap).
2. The core gateway is pre-configured to `include /etc/nginx/conf.d/addons/*.conf`.
3. The ConfigMap is mounted as a file into the gateway's addon directory.

---

## Troubleshooting

### Verify Installation
```bash
# Check pod status
kubectl get pods -n sunbird -l app.kubernetes.io/name=dial

# Check logs for DB connection issues
kubectl logs -n sunbird -l app.kubernetes.io/name=dial -f

# Test health endpoint locally
kubectl port-forward -n sunbird svc/dial-service 9000:9000
curl http://localhost:9000/health
```

### Manual Cleanup
If you need to destroy only the DIAL storage container:
1. Ensure `destroy_resources` is uncommented in `script/addon.sh`.
2. Run `./script/addon.sh uninstall azure`.
