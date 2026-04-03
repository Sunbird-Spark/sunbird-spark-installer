#!/bin/bash
# upgrade_chart.sh — Deploy or upgrade a single subchart within a bundle without
# affecting any other running service.
#
# Usage (run from your environment directory):
#   ./upgrade_chart.sh <bundle> <chart>
#
# Examples:
#   ./upgrade_chart.sh learnbb lern
#   ./upgrade_chart.sh learnbb keycloak
#   ./upgrade_chart.sh learnbb kafka
#   ./upgrade_chart.sh edbb player
#   ./upgrade_chart.sh edbb kong
#   ./upgrade_chart.sh knowledgebb knowlg
#   ./upgrade_chart.sh knowledgebb search
#
# How it works:
#   Phase A — No existing Helm release for the bundle:
#     Reads Chart.yaml to find all charts that have a condition: flag.
#     Sets --set <target>.enabled=true and --set <other>.enabled=false for every
#     other conditional chart so only the target is deployed on a fresh cluster.
#
#   Phase B — Helm release already exists:
#     Uses --reuse-values to preserve the previous release state exactly as-is
#     (all previously deployed charts remain untouched), then adds
#     --set <target>.enabled=true to bring up or update only the target chart.
#
# Note: install.sh is not modified. All existing install.sh functionality is unchanged.

set -euo pipefail

# ---------------------------------------------------------------------------
# Validate arguments
# ---------------------------------------------------------------------------
if [ $# -ne 2 ]; then
    echo "Usage: ./upgrade_chart.sh <bundle> <chart>"
    echo ""
    echo "Bundles and their available charts:"
    echo "  learnbb     — lern, keycloak, keycloak-kids-keys, flink, adminutil,"
    echo "                cert, certificateapi, certificatesign, certregistry,"
    echo "                registry, kafka, redis, elasticsearch, yugabyte"
    echo "  edbb        — player, kong, kong-apis, kong-consumers, knowledgemw,"
    echo "                echo, nginx-public-ingress, nginx-private-ingress,"
    echo "                router, kafka, yugabyte"
    echo "  knowledgebb — knowlg, search, flink, janusgraph, kafka, elasticsearch,"
    echo "                yugabyte"
    echo "  obsrvbb     — telemetry, superset, kafka, yugabyte"
    echo "  additional  — nlweb, nlwebflink, velero, volume-autoscaler"
    echo "  monitoring  — (deploy the full bundle via install.sh install_component)"
    exit 1
fi

bundle="$1"
target_chart="$2"

# ---------------------------------------------------------------------------
# Resolve paths — script is run from the environment directory
# (e.g. opentofu/azure/<env-name>/) just like install.sh
# ---------------------------------------------------------------------------
environment=$(basename "$(pwd)")

# Navigate to helmcharts directory (same as install.sh does)
current_directory="$(pwd)"
if [ "$(basename "$current_directory")" != "helmcharts" ]; then
    cd ../../../helmcharts 2>/dev/null || true
fi

# Verify the bundle and chart exist
if [ ! -d "$bundle" ]; then
    echo "Error: bundle '$bundle' not found in helmcharts/"
    exit 1
fi
if [ ! -d "$bundle/charts/$target_chart" ]; then
    echo "Error: chart '$target_chart' not found in helmcharts/$bundle/charts/"
    exit 1
fi

# ---------------------------------------------------------------------------
# Build optional value flags — mirrors install.sh install_component logic
# ---------------------------------------------------------------------------

# Include ed-values.yaml if present (e.g. edbb uses it)
ed_values_flag=""
if [ -f "$bundle/ed-values.yaml" ]; then
    ed_values_flag="-f $bundle/ed-values.yaml"
fi

# Include DIAL addon values if the addon is deployed
addon_values_flag=""
if [ "$(yq '.deployed_dial_addon' "../opentofu/azure/$environment/global-values.yaml")" = "true" ]; then
    if [ -f "../addons/global-cloud-values.yaml" ]; then
        addon_values_flag="-f ../addons/global-cloud-values.yaml"
    fi
fi


# ---------------------------------------------------------------------------
# Phase A / Phase B — check if the bundle's Helm release already exists
# ---------------------------------------------------------------------------
if helm status "$bundle" --namespace sunbird &>/dev/null; then

    # -------------------------------------------------------------------------
    # Phase B: Release exists.
    # --reuse-values loads all values from the previous release so every
    # previously deployed chart stays exactly as-is.
    # --set <target>.enabled=true adds or updates only the target chart.
    # No other pods are restarted or deleted.
    # -------------------------------------------------------------------------
    echo -e "\nRelease '$bundle' exists — upgrading '$target_chart' only (Phase B)"

    # ---------------------------------------------------------------------------
    # Bitnami stateful chart password re-passing
    # Bitnami charts require existing passwords to be passed explicitly on upgrade
    # (they live in k8s secrets, not in Helm values, so --reuse-values doesn't help)
    # ---------------------------------------------------------------------------
    bitnami_password_flags=""
    case "$target_chart" in
        kafka)
            if kubectl get secret kafka-user-passwords -n sunbird &>/dev/null; then
                INTER_BROKER_PASSWORD=$(kubectl get secret kafka-user-passwords -n sunbird \
                    -o jsonpath="{.data.inter-broker-password}" | base64 -d)
                CONTROLLER_PASSWORD=$(kubectl get secret kafka-user-passwords -n sunbird \
                    -o jsonpath="{.data.controller-password}" | base64 -d)
                bitnami_password_flags="--set kafka.sasl.interbroker.password=${INTER_BROKER_PASSWORD} --set kafka.sasl.controller.password=${CONTROLLER_PASSWORD}"
                echo "Fetched existing Kafka passwords from k8s secret"
            fi
            ;;
        elasticsearch)
            if kubectl get secret elasticsearch -n sunbird &>/dev/null; then
                ES_PASSWORD=$(kubectl get secret elasticsearch -n sunbird \
                    -o jsonpath="{.data.elasticsearch-password}" | base64 -d)
                bitnami_password_flags="--set elasticsearch.security.elasticPassword=${ES_PASSWORD}"
                echo "Fetched existing Elasticsearch password from k8s secret"
            fi
            ;;
        redis)
            if kubectl get secret redis -n sunbird &>/dev/null; then
                REDIS_PASSWORD=$(kubectl get secret redis -n sunbird \
                    -o jsonpath="{.data.redis-password}" | base64 -d)
                bitnami_password_flags="--set redis.auth.password=${REDIS_PASSWORD}"
                echo "Fetched existing Redis password from k8s secret"
            fi
            ;;
    esac

    helm upgrade "$bundle" "$bundle" \
        --namespace sunbird \
        --reuse-values \
        --set "${target_chart}.enabled=true" \
        $ed_values_flag \
        $addon_values_flag \
        -f images.yaml \
        -f "global-resources.yaml" \
        -f "../opentofu/azure/$environment/global-values.yaml" \
        -f "../opentofu/azure/$environment/global-cloud-values.yaml" \
        $bitnami_password_flags \
        --timeout 30m \
        --debug

else

    # -------------------------------------------------------------------------
    # Phase A: No release yet — first deploy of this bundle.
    # Read all charts with a condition: flag from Chart.yaml.
    # Enable only the target; explicitly disable all others so they are not
    # auto-deployed by Helm from the charts/ directory.
    # -------------------------------------------------------------------------
    echo -e "\nNo existing release for '$bundle' — deploying '$target_chart' only (Phase A)"

    # Build --set flags: enable target, disable every other conditional chart
    set_flags="--set ${target_chart}.enabled=true"
    while IFS= read -r chart_name; do
        if [ "$chart_name" != "$target_chart" ]; then
            set_flags="$set_flags --set ${chart_name}.enabled=false"
        fi
    done < <(yq '.dependencies[] | select(has("condition")) | .name' "$bundle/Chart.yaml")

    helm upgrade --install "$bundle" "$bundle" \
        --namespace sunbird \
        $ed_values_flag \
        $addon_values_flag \
        -f images.yaml \
        -f "global-resources.yaml" \
        -f "../opentofu/azure/$environment/global-values.yaml" \
        -f "../opentofu/azure/$environment/global-cloud-values.yaml" \
        $set_flags \
        --timeout 30m \
        --debug

fi
