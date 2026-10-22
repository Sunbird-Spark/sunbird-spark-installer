#!/usr/bin/env bash
#
# Fix for the subnet half of CSPM BLOCKER remediation Step 2
# (azure-blocker-fixes.md): the AKS subnet needs the Microsoft.Storage VNet Service
# Endpoint enabled so backend services keep reaching storage once the account's
# network access gets locked down later. Terraform already handles this
# automatically when it creates the VNet from scratch (skip_network_module: false,
# see opentofu/azure/modules/network/main.tf:64). This script covers the other
# case: reusing an existing VNet (skip_network_module: true), where Terraform can't
# safely take ownership of a subnet it doesn't fully manage (see azure-blocker-fixes.md
# for why) -- so the fix is a single, targeted `az` command instead.
#
# Dry run by default -- only reports. --apply actually updates the subnet.
# Safe to re-run: skips if the endpoint is already present, and preserves any other
# service endpoints already configured on the subnet rather than overwriting them.
#
# Prerequisites: `az login` and `az account set --subscription <id>` already done.
#                `yq` (mikefarah/yq v4) available on PATH.
#
# Usage (run from inside an environment directory, e.g. opentofu/azure/<env-name>/,
# or point it at a specific global-values.yaml):
#   ./enable-storage-service-endpoint.sh [--config global-values.yaml] [--apply]

set -euo pipefail

CONFIG="./global-values.yaml"
APPLY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --apply) APPLY=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [ ! -f "$CONFIG" ]; then
  echo "Config file not found: $CONFIG"
  echo "Run this from inside an environment directory (opentofu/azure/<env-name>/),"
  echo "or pass --config /path/to/global-values.yaml."
  exit 1
fi

skip_network_module=$(yq '.global.skip_network_module' "$CONFIG")

if [ "$skip_network_module" = "false" ]; then
  echo "skip_network_module is false -- Terraform creates the VNet and already"
  echo "configures the Microsoft.Storage service endpoint (network/main.tf). Nothing to do."
  exit 0
fi

resource_group=$(yq '.global.resource_group_name' "$CONFIG")
vnet_name=$(yq '.global.vnet_name' "$CONFIG")
subnet_name=$(yq '.global.aks_subnet_name' "$CONFIG")

if [ -z "$resource_group" ] || [ -z "$vnet_name" ] || [ -z "$subnet_name" ]; then
  echo "skip_network_module is true, but resource_group_name/vnet_name/aks_subnet_name"
  echo "are not fully set in $CONFIG. Fill these in before running this script."
  exit 1
fi

echo "Checking current service endpoints on subnet '$subnet_name' (VNet '$vnet_name', resource group '$resource_group')..."
if ! current_endpoints=$(az network vnet subnet show \
  --resource-group "$resource_group" \
  --vnet-name "$vnet_name" \
  --name "$subnet_name" \
  --query "serviceEndpoints[].service" -o tsv); then
  echo "Failed to look up subnet '$subnet_name' via az -- check that az is installed and"
  echo "authenticated (az login), the subnet/vnet/resource group names in $CONFIG are"
  echo "correct, and the subnet actually exists. Not guessing at the current state."
  exit 1
fi

if echo "$current_endpoints" | grep -qx "Microsoft.Storage"; then
  echo "Microsoft.Storage service endpoint already present. Nothing to do."
  exit 0
fi

new_endpoints="Microsoft.Storage"
if [ -n "$current_endpoints" ]; then
  new_endpoints="${current_endpoints//$'\n'/ } Microsoft.Storage"
fi

echo "Microsoft.Storage service endpoint is missing."
echo "Current endpoints: ${current_endpoints:-<none>}"
echo "Would set endpoints to: $new_endpoints"

if [ "$APPLY" = false ]; then
  echo "[dry-run] Would run: az network vnet subnet update --resource-group $resource_group --vnet-name $vnet_name --name $subnet_name --service-endpoints $new_endpoints"
  echo "Re-run with --apply to actually make this change."
  exit 0
fi

# new_endpoints is an intentionally space-separated list of service names, not a single value
# shellcheck disable=SC2086
az network vnet subnet update \
  --resource-group "$resource_group" \
  --vnet-name "$vnet_name" \
  --name "$subnet_name" \
  --service-endpoints $new_endpoints

echo "Done. Microsoft.Storage service endpoint added to '$subnet_name'."
