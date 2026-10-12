#!/usr/bin/env bash
#
# One-time fix for the "compute hygiene" SAFE findings from azure-csm-fix-plan.md that
# could NOT be done via this repo's OpenTofu, because the target VMs are created outside
# this repo's Terraform state (e.g. Jenkins/runner/ops VMs standing up CI or admin access).
#
# Which VMs to fix is NOT hardcoded here -- every deployment of sunbird-spark-installer
# names its standalone VMs differently. List yours in a vms.yaml (see vms.yaml in this
# same folder for the format) and pass it with --config, or rely on the default below.
#
# Covers 3 CSPM controls:
#   1. Disk Network Access should not allow public access from all networks -- SAFE
#   2. Internet-facing VMs should be protected with NSGs                    -- SAFE
#   3. System updates should be installed                                   -- SAFE, but can trigger a service restart
#
# This is NOT meant to run unattended against production. Whether this is a dry run
# or actually applies changes is controlled by the "apply:" key in vms.yaml (defaults
# to false = dry run there). --apply / --dry-run on the command line override whatever
# the file says, for a one-off run without editing the file. Step 3 (OS updates)
# additionally requires typing the VM name to confirm, one VM at a time, since it
# carries real risk (can restart a service).
#
# Prerequisites: `az login` and `az account set --subscription <id>` already done.
#                `yq` (mikefarah/yq v4) available on PATH.
#
# Usage:
#   ./fix-compute-hygiene.sh [--config vms.yaml] [--apply | --dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/vms.yaml"
APPLY_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY_OVERRIDE=true; shift ;;
    --dry-run) APPLY_OVERRIDE=false; shift ;;
    --config) CONFIG="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [ ! -f "$CONFIG" ]; then
  echo "Config file not found: $CONFIG"
  echo "Copy vms.yaml, fill in your own VM names + resource groups, and pass it with --config."
  exit 1
fi

if [ -n "$APPLY_OVERRIDE" ]; then
  APPLY="$APPLY_OVERRIDE"
else
  APPLY=$(yq '.apply // false' "$CONFIG")
fi

VM_COUNT=$(yq '.vms | length' "$CONFIG")
if [ "$VM_COUNT" -eq 0 ]; then
  echo "No VMs listed in $CONFIG -- nothing to do."
  exit 0
fi

VM_NAMES=()
VM_RGS=()
for i in $(seq 0 $((VM_COUNT - 1))); do
  name=$(yq ".vms[$i].name" "$CONFIG")
  rg=$(yq ".vms[$i].resource_group" "$CONFIG")
  if [ "$name" = "REPLACE_WITH_VM_NAME" ] || [ "$rg" = "REPLACE_WITH_RESOURCE_GROUP" ]; then
    echo "Entry $i in $CONFIG still has a placeholder value -- fill in real VM names/resource groups first."
    exit 1
  fi
  VM_NAMES+=("$name")
  VM_RGS+=("$rg")
done

echo "Loaded ${#VM_NAMES[@]} VM(s) from $CONFIG: ${VM_NAMES[*]}"
if [ "$APPLY" = false ]; then
  echo "=== DRY RUN (no changes will be made). Pass --apply to actually apply fixes. ==="
fi

run() {
  if [ "$APPLY" = true ]; then
    "$@"
  else
    echo "[dry-run] $*"
  fi
}

confirm_vm() {
  local vm_name=$1
  local prompt=$2
  read -r -p "${prompt} Type the VM name (${vm_name}) to confirm, anything else to skip: " answer
  [ "$answer" = "$vm_name" ]
}

echo
echo "### 1. Disk Network Access -- deny public access on each VM's OS disk (SAFE, no app impact) ###"
for idx in "${!VM_NAMES[@]}"; do
  vm="${VM_NAMES[$idx]}"
  rg="${VM_RGS[$idx]}"
  disk_id=$(az vm show --name "$vm" --resource-group "$rg" --query "storageProfile.osDisk.managedDisk.id" -o tsv)
  if [ -z "$disk_id" ]; then
    echo "Skipping $vm -- VM not found in resource group $rg."
    continue
  fi
  current_policy=$(az disk show --ids "$disk_id" --query "networkAccessPolicy" -o tsv)
  if [ "$current_policy" = "DenyAll" ]; then
    echo "$vm: disk already DenyAll, skipping."
    continue
  fi
  echo "$vm: disk network access is '$current_policy' -> setting to DenyAll"
  run az disk update --ids "$disk_id" --network-access-policy DenyAll
done

echo
echo "### 2. Internet-facing VMs -- ensure an NSG is attached (SAFE, additive only) ###"
for idx in "${!VM_NAMES[@]}"; do
  vm="${VM_NAMES[$idx]}"
  rg="${VM_RGS[$idx]}"
  nic_id=$(az vm show --name "$vm" --resource-group "$rg" --query "networkProfile.networkInterfaces[0].id" -o tsv)
  [ -z "$nic_id" ] && { echo "Skipping $vm -- VM not found in resource group $rg."; continue; }
  existing_nsg=$(az network nic show --ids "$nic_id" --query "networkSecurityGroup.id" -o tsv)
  if [ -n "$existing_nsg" ]; then
    echo "$vm: NIC already has an NSG attached, skipping."
    continue
  fi
  nsg_name="${vm}-nsg"
  # NOTE: a brand-new NSG is NOT "no rules = allow everything" -- Azure NSGs carry a
  # built-in DenyAllInBound default (priority 65500) for anything outside the VNet.
  # Attaching an empty NSG to a VM that currently has none would cut off its inbound
  # traffic the instant it attaches. The temp-allow-inbound rule below mirrors
  # "no NSG" behaviour so nothing breaks; tightening this to only the ports actually
  # needed is a deliberate follow-up, not something this script decides on its own
  # (same caveat as the plan doc's NSG port-audit finding).
  echo "$vm: no NSG attached -- creating '$nsg_name' with a temporary allow-all-inbound rule (preserves current traffic) and attaching it"
  run az network nsg create --name "$nsg_name" --resource-group "$rg"
  run az network nsg rule create \
    --nsg-name "$nsg_name" --resource-group "$rg" \
    --name temp-allow-all-inbound --priority 100 \
    --direction Inbound --access Allow --protocol "*" \
    --source-address-prefixes "*" --source-port-ranges "*" \
    --destination-address-prefixes "*" --destination-port-ranges "*"
  run az network nic update --ids "$nic_id" --network-security-group "$nsg_name"
  echo "$vm: TODO -- replace 'temp-allow-all-inbound' with rules scoped to only the ports this VM actually needs."
done

echo
echo "### 3. Apply pending OS updates (can restart services -- run in a maintenance window) ###"
for idx in "${!VM_NAMES[@]}"; do
  vm="${VM_NAMES[$idx]}"
  rg="${VM_RGS[$idx]}"

  echo
  echo "--- $vm ---"
  if [ "$APPLY" = false ]; then
    echo "[dry-run] Would prompt to confirm before patching $vm."
    continue
  fi

  if confirm_vm "$vm" "Apply OS updates on $vm now? Only do this in a maintenance window."; then
    az vm run-command invoke \
      --name "$vm" --resource-group "$rg" \
      --command-id RunShellScript \
      --scripts "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
    echo "$vm: updates applied."
  else
    echo "$vm: skipped."
  fi
done

echo
echo "Done. Re-run with --apply if this was a dry run."
