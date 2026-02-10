#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(dirname "$SCRIPT_DIR")"
CHART_DIR="$ADDON_DIR/video-stream-generator"
REPO_ROOT="$(cd "$ADDON_DIR/../.." && pwd)"

DEFAULT_NAMESPACE="sunbird"
DEFAULT_RELEASE_NAME="video-stream-generator"

NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"
RELEASE_NAME="${RELEASE_NAME:-$DEFAULT_RELEASE_NAME}"
ACTION="$1"
shift 2>/dev/null || true

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace) NAMESPACE="$2"; shift 2 ;;
        -r|--release) RELEASE_NAME="$2"; shift 2 ;;
        -f|--values) VALUES_FILE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ "$ACTION" = "install" ]; then
    cd "$CHART_DIR"
        
    # Detect cloud provider
    if [ -f "$REPO_ROOT/opentofu/azure/template/global-values.yaml" ]; then
        CLOUD_DIR="$REPO_ROOT/opentofu/azure/template"
    elif [ -f "$REPO_ROOT/opentofu/gcp/template/global-values.yaml" ]; then
        CLOUD_DIR="$REPO_ROOT/opentofu/gcp/template"
    else
        echo "ERROR: No opentofu global-values.yaml found"
        exit 1
    fi
    
    # 1. Base global values from opentofu
    HELM_ARGS="-f $CLOUD_DIR/global-values.yaml"
    
    # 2. Cloud-generated values (optional)
    if [ -f "$CLOUD_DIR/global-cloud-values.yaml" ]; then
        HELM_ARGS="$HELM_ARGS -f $CLOUD_DIR/global-cloud-values.yaml"
    fi
    
    # 3. Addon-specific global values
    HELM_ARGS="$HELM_ARGS -f $ADDON_DIR/global-values.yaml"
    
    # 4. Custom values file if provided
    [ -n "$VALUES_FILE" ] && HELM_ARGS="$HELM_ARGS -f $VALUES_FILE"
    
    helm upgrade --install "$RELEASE_NAME" . --namespace "$NAMESPACE" $HELM_ARGS
    
    echo "Video Stream Generator deployed successfully"

elif [ "$ACTION" = "uninstall" ]; then
    helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE"
    echo "Video Stream Generator uninstalled"
else
    echo "Usage: $0 [install|uninstall] [-n namespace] [-r release] [-f values-file]"
    exit 1
fi
