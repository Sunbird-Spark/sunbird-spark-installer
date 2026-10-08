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
    local service_name="$1"
    local chart_dir="$HELMCHARTS_DIR/$service_name"
    
    echo "Deploying $service_name Helm chart..."
    cd "$chart_dir"
    
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

    helm upgrade --install "$service_name" . --namespace "$NAMESPACE" $helm_args
    echo "$service_name deployed successfully"
}

uninstall_service() {
    local service_name="$1"
    echo "Uninstalling $service_name Helm chart..."
    helm uninstall "$service_name" --namespace "$NAMESPACE" || echo "Helm release $service_name not found, skipping."
}

post_install_nodebb_plugins() {
    echo ">> Waiting for NodeBB deployment to be ready..."
    kubectl rollout status deployment nodebb -n "$NAMESPACE" --timeout=300s

    echo ">> Activating NodeBB plugins..."
    kubectl exec -n "$NAMESPACE" deploy/nodebb -- ./nodebb activate nodebb-plugin-create-forum
    kubectl exec -n "$NAMESPACE" deploy/nodebb -- ./nodebb activate nodebb-plugin-sunbird-oidc
    kubectl exec -n "$NAMESPACE" deploy/nodebb -- ./nodebb activate nodebb-plugin-write-api

    echo ">> Rebuilding NodeBB to apply plugin changes..."
    kubectl exec -n "$NAMESPACE" deploy/nodebb -- ./nodebb build

    echo ">> Restarting NodeBB..."
    kubectl delete pod -n "$NAMESPACE" -l app.kubernetes.io/name=nodebb

    echo "NodeBB plugins are activated, built, and NodeBB has been restarted."
}

install() {
    echo "Installing Discussion Forum services..."
    for SERVICE in "${SERVICES[@]}"; do
        deploy_service "$SERVICE"
    done
    post_install_nodebb_plugins
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
