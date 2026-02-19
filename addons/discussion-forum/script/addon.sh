#!/bin/bash
set -e

# PATHS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(dirname "$SCRIPT_DIR")"
HELMCHARTS_DIR="$ADDON_DIR/helmcharts"
REPO_ROOT="$(cd "$ADDON_DIR/../.." && pwd)"

# DEFAULTS
NAMESPACE="sunbird"
ACTION="$1"
CLOUD_PROVIDER="${2:-azure}" # Default to azure if not provided

# Service names — order matters: APIs and consumers are registered before services start
SERVICES=("discussion-forum-apis" "discussion-forum-consumers" "discussionmw" "nodebb" "groups")

deploy_service() {
    local SERVICE_NAME="$1"
    local CHART_DIR="$HELMCHARTS_DIR/$SERVICE_NAME"
    
    echo "Deploying $SERVICE_NAME Helm chart..."
    cd "$CHART_DIR"
    
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
    HELM_ARGS="-f $CLOUD_DIR/global-values.yaml"
    HELM_ARGS="$HELM_ARGS -f $CLOUD_DIR/global-cloud-values.yaml"
    HELM_ARGS="$HELM_ARGS -f $REPO_ROOT/addons/global-values.yaml"
    HELM_ARGS="$HELM_ARGS -f $REPO_ROOT/addons/images.yaml"
    
    helm upgrade --install "$SERVICE_NAME" . --namespace "$NAMESPACE" $HELM_ARGS
    echo "$SERVICE_NAME deployed successfully"
}

uninstall_service() {
    local SERVICE_NAME="$1"
    echo "Uninstalling $SERVICE_NAME Helm chart..."
    helm uninstall "$SERVICE_NAME" --namespace "$NAMESPACE" || echo "Helm release $SERVICE_NAME not found, skipping."
}

install() {
    echo "Installing Discussion Forum services..."
    for SERVICE in "${SERVICES[@]}"; do
        deploy_service "$SERVICE"
    done
    echo "All Discussion Forum services deployed successfully"
}

uninstall() {
    echo "Uninstalling Discussion Forum services..."
    for SERVICE in "${SERVICES[@]}"; do
        uninstall_service "$SERVICE"
    done
    echo "All Discussion Forum services uninstalled successfully"
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
        echo ""
        echo "This script manages the Discussion Forum addon services:"
        echo "  - discussion-forum-apis: Registers discussion-forum Kong API routes"
        echo "  - discussion-forum-consumers: Grants discussion/groups ACL groups to core consumers"
        echo "  - discussionmw: Discussion middleware service"
        echo "  - nodebb: NodeBB forum platform"
        echo "  - groups: Groups service"
        echo ""
        echo "Examples:"
        echo "  export ENV_NAME=demo"
        echo "  $0 install azure"
        echo "  $0 uninstall"
        exit 1
        ;;
esac
