#!/bin/bash
set -e

# PATHS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$ADDON_DIR/helmchart/video-stream-generator"
REPO_ROOT="$(cd "$ADDON_DIR/../.." && pwd)"

# DEFAULTS
NAMESPACE="sunbird"
RELEASE_NAME="video-stream-generator"
ACTION="$1"
CLOUD_PROVIDER="${2:-azure}" # Default to azure if not provided

deploy_chart() {
    echo "Deploying Video Stream Generator Helm chart..."
    cd "$CHART_DIR"
    
    local CLOUD_DIR="$REPO_ROOT/opentofu/$CLOUD_PROVIDER/template"
    
    # Check for required configuration files
    if [ ! -f "$CLOUD_DIR/global-values.yaml" ] || [ ! -f "$CLOUD_DIR/global-cloud-values.yaml" ]; then
        echo "ERROR: OpenTofu global values not found in $CLOUD_DIR. Please run opentofu first."
        exit 1
    fi
    
    # Standard values layering
    HELM_ARGS="-f $CLOUD_DIR/global-values.yaml"
    HELM_ARGS="$HELM_ARGS -f $CLOUD_DIR/global-cloud-values.yaml"
    HELM_ARGS="$HELM_ARGS -f $REPO_ROOT/addons/global-values.yaml"
    
    helm upgrade --install "$RELEASE_NAME" . --namespace "$NAMESPACE" $HELM_ARGS
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
