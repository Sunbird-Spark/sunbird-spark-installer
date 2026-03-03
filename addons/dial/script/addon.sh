#!/bin/bash
set -e

# PATHS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$ADDON_DIR/../.." && pwd)"

# DEFAULTS
NAMESPACE="sunbird"
ACTION="$1"
CLOUD_PROVIDER="${2:-azure}" # Default to azure if not provided

# List of charts to manage
CHARTS=("dial" "dialcode-context-updater")

provision_resources() {
    local provider_dir="$ADDON_DIR/opentofu/$CLOUD_PROVIDER"
    if [ -d "$provider_dir" ]; then
        echo "Provisioning cloud resources for $CLOUD_PROVIDER using Terragrunt..."
        pushd "$provider_dir" > /dev/null
        terragrunt run-all plan --terragrunt-non-interactive
        terragrunt run-all apply --terragrunt-non-interactive
        popd > /dev/null
    else
        echo "No cloud resources to provision for $CLOUD_PROVIDER"
    fi
}

deploy_chart() {
    if [ -z "$ENV_NAME" ]; then
        echo "ERROR: ENV_NAME environment variable is not set. Please export it (e.g., export ENV_NAME=demo) before running this script."
        exit 1
    fi
    local CLOUD_DIR="$REPO_ROOT/opentofu/$CLOUD_PROVIDER/$ENV_NAME"
    
    # Check for required configuration files
    if [ ! -f "$CLOUD_DIR/global-values.yaml" ] || [ ! -f "$CLOUD_DIR/global-cloud-values.yaml" ]; then
        echo "ERROR: OpenTofu global values not found in $CLOUD_DIR. Please run opentofu first."
        exit 1
    fi
    
    # Standard values layering
    local HELM_ARGS="-f $CLOUD_DIR/global-values.yaml"
    HELM_ARGS="$HELM_ARGS -f $CLOUD_DIR/global-cloud-values.yaml"
    HELM_ARGS="$HELM_ARGS -f $REPO_ROOT/addons/global-values.yaml"
    HELM_ARGS="$HELM_ARGS -f $REPO_ROOT/addons/images.yaml"

    for chart in "${CHARTS[@]}"; do
        echo "Deploying $chart Helm chart..."
        local chart_path="$ADDON_DIR/helmcharts/$chart"
        if [ -d "$chart_path" ]; then
            helm upgrade --install "$chart" "$chart_path" --namespace "$NAMESPACE" $HELM_ARGS
            echo "$chart service deployed successfully"
        else
            echo "Warning: Chart directory $chart_path not found. Skipping."
        fi
    done
}

uninstall_chart() {
    for chart in "${CHARTS[@]}"; do
        echo "Uninstalling $chart Helm chart..."
        helm uninstall "$chart" --namespace "$NAMESPACE" || echo "Helm release $chart not found, skipping."
    done
}

destroy_resources() {
    local provider_dir="$ADDON_DIR/opentofu/$CLOUD_PROVIDER"
    if [ -d "$provider_dir" ]; then
        echo "Destroying cloud resources for $CLOUD_PROVIDER using Terragrunt..."
        pushd "$provider_dir" > /dev/null
        terragrunt run-all plan -destroy --terragrunt-non-interactive
        terragrunt run-all destroy --terragrunt-non-interactive
        popd > /dev/null
    fi
}

install() {
    # provision_resources
    deploy_chart
}

uninstall() {
    uninstall_chart
    # By default, resource destruction is disabled for safety. 
    # Uncomment the line below to enable automatic cleanup.
    # destroy_resources
}

# --- Main Execution ---
case "$ACTION" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo "Usage: $0 [install|uninstall] [azure|gcp]"
        exit 1
        ;;
esac
