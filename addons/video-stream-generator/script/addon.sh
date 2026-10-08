#!/bin/bash
set -e

# PATHS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$ADDON_DIR/helmcharts/video-stream-generator"
REPO_ROOT="$(cd "$ADDON_DIR/../.." && pwd)"

# DEFAULTS
NAMESPACE="sunbird"
RELEASE_NAME="video-stream-generator"
ACTION="$1"
CLOUD_PROVIDER="${2:-azure}" # Default to azure if not provided

deploy_chart() {
    echo "Deploying Video Stream Generator Helm chart..."
    cd "$CHART_DIR"
    
    if [[ -z "$ENV_NAME" ]]; then
        echo "ERROR: ENV_NAME environment variable is not set. Please export it (e.g., export ENV_NAME=demo) before running this script." >&2
        exit 1
    fi
    local cloud_dir="$REPO_ROOT/opentofu/$CLOUD_PROVIDER/$ENV_NAME"
    
    # Check for required configuration files
    if [[ ! -f "$cloud_dir/global-values.yaml" ]] || [[ ! -f "$cloud_dir/global-cloud-values.yaml" ]]; then
        echo "ERROR: OpenTofu global values not found in $cloud_dir. Please run opentofu first." >&2
        exit 1
    fi
    
    # Standard values layering
    local helm_args="-f $cloud_dir/global-values.yaml"
    helm_args="$helm_args -f $cloud_dir/global-cloud-values.yaml"
    helm_args="$helm_args -f $REPO_ROOT/addons/global-values.yaml"
    helm_args="$helm_args -f $REPO_ROOT/addons/images.yaml"

    helm upgrade --install "$RELEASE_NAME" . --namespace "$NAMESPACE" $helm_args
    echo "Video Stream Generator deployed successfully"
}

uninstall_chart() {
    echo "Uninstalling Video Stream Generator Helm chart..."
    helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE" || echo "Helm release not found, skipping."
}

install() {
    deploy_chart
}

uninstall() {
    uninstall_chart
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
