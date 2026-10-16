#!/usr/bin/env bash
#
# Fix for the CSPM "HTTP(S) access from the Internet should be restricted" finding.
# Auto-discovers every NSG (no need to list names manually), skips the ones you've
# marked as intentionally public (e.g. the one fronting nginx-public-ingress), and
# flags/optionally removes any rule on the rest that allows port 80/443 from anyone.
#
# Why not auto-detect the ingress NSG too: tracing "which NSG backs the ingress
# public IP" through the load balancer/NIC chain is fragile and AKS-networking-setup
# dependent (differs by CNI plugin, LB SKU, whether AKS even attaches a per-NIC NSG
# vs. managing one internally). Telling the script explicitly via --ignore is more
# reliable than guessing wrong and skipping (or worse, not skipping) the real ingress.
#
# Dry run by default -- only reports. Deleting a flagged rule requires --apply AND
# typing the NSG name to confirm, one NSG at a time, same reasoning as why
# fix-compute-hygiene.sh gates SSH/patching behind a confirmation: we can't know for
# certain nothing else depends on that open rule.
#
# Prerequisites: `az login` and `az account set --subscription <id>` already done.
#                `jq` available on PATH.
#
# Usage:
#   ./review-public-http-nsgs.sh [--resource-group <rg>] [--ignore <nsg-name>]... [--apply]
#
# Examples:
#   ./review-public-http-nsgs.sh --ignore nginx-public-ingress-nsg
#   ./review-public-http-nsgs.sh --resource-group ed-coss --ignore nginx-public-ingress-nsg --apply

set -euo pipefail

RESOURCE_GROUP=""
APPLY=false
IGNORE_LIST=()

while [ $# -gt 0 ]; do
  case "$1" in
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --ignore) IGNORE_LIST+=("$2"); shift 2 ;;
    --apply) APPLY=true; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [ "${#IGNORE_LIST[@]}" -eq 0 ]; then
  echo "Warning: no --ignore given. If your ingress NSG isn't excluded, it will be"
  echo "reviewed (and, with --apply, have its public rule removed) like any other --"
  echo "that would take the platform offline. Re-run with --ignore <ingress-nsg-name>."
  echo
fi

echo "Discovering NSGs..."
if [ -n "$RESOURCE_GROUP" ]; then
  nsgs_json=$(az network nsg list --resource-group "$RESOURCE_GROUP" -o json)
else
  nsgs_json=$(az network nsg list -o json)
fi

nsg_count=$(echo "$nsgs_json" | jq 'length')
if [ "$nsg_count" -eq 0 ]; then
  echo "No NSGs found."
  exit 0
fi

is_ignored() {
  local name="$1"
  for ignored in "${IGNORE_LIST[@]:-}"; do
    [ "$name" = "$ignored" ] && return 0
  done
  return 1
}

# True if the given port spec (e.g. "*", "80", "443", "1-1000") includes port 80 or 443.
port_spec_includes_http() {
  local spec="$1"
  if [ "$spec" = "*" ]; then
    return 0
  fi
  if [[ "$spec" == *-* ]]; then
    local start="${spec%%-*}"
    local end="${spec##*-}"
    if [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]]; then
      if [ "$start" -le 80 ] && [ 80 -le "$end" ]; then return 0; fi
      if [ "$start" -le 443 ] && [ 443 -le "$end" ]; then return 0; fi
    fi
    return 1
  fi
  [ "$spec" = "80" ] || [ "$spec" = "443" ]
}

# True if the given source spec represents "anyone on the internet".
source_spec_is_wildcard() {
  local spec="$1"
  [ "$spec" = "*" ] || [ "$spec" = "Internet" ] || [ "$spec" = "0.0.0.0/0" ]
}

confirm_nsg() {
  local nsg_name="$1"
  local rule_name="$2"
  read -r -p "Delete rule '$rule_name' on NSG '$nsg_name'? Type the NSG name ($nsg_name) to confirm, anything else to skip: " answer
  [ "$answer" = "$nsg_name" ]
}

reviewed_count=0
flagged_count=0
removed_count=0

for i in $(seq 0 $((nsg_count - 1))); do
  name=$(echo "$nsgs_json" | jq -r ".[$i].name")
  rg=$(echo "$nsgs_json" | jq -r ".[$i].resourceGroup")

  if is_ignored "$name"; then
    echo "Skipping $name (resource group $rg) -- in --ignore list."
    continue
  fi

  reviewed_count=$((reviewed_count + 1))
  echo
  echo "--- Reviewing $name (resource group $rg) ---"

  rules_json=$(az network nsg rule list --nsg-name "$name" --resource-group "$rg" -o json 2>/dev/null || echo "[]")
  rule_count=$(echo "$rules_json" | jq 'length')
  found_in_nsg=false

  for r in $(seq 0 $((rule_count - 1))); do
    direction=$(echo "$rules_json" | jq -r ".[$r].direction")
    access=$(echo "$rules_json" | jq -r ".[$r].access")
    rule_name=$(echo "$rules_json" | jq -r ".[$r].name")

    if [ "$direction" != "Inbound" ] || [ "$access" != "Allow" ]; then
      continue
    fi

    sources=$(echo "$rules_json" | jq -r ".[$r].sourceAddressPrefix // empty")
    if [ -z "$sources" ]; then
      sources=$(echo "$rules_json" | jq -r ".[$r].sourceAddressPrefixes[]? // empty")
    fi

    ports=$(echo "$rules_json" | jq -r ".[$r].destinationPortRange // empty")
    if [ -z "$ports" ]; then
      ports=$(echo "$rules_json" | jq -r ".[$r].destinationPortRanges[]? // empty")
    fi

    wildcard_source=false
    while IFS= read -r src; do
      [ -z "$src" ] && continue
      if source_spec_is_wildcard "$src"; then
        wildcard_source=true
      fi
    done <<< "$sources"

    http_port=false
    while IFS= read -r port; do
      [ -z "$port" ] && continue
      if port_spec_includes_http "$port"; then
        http_port=true
      fi
    done <<< "$ports"

    if [ "$wildcard_source" = true ] && [ "$http_port" = true ]; then
      found_in_nsg=true
      flagged_count=$((flagged_count + 1))
      echo "  FLAGGED: rule '$rule_name' allows inbound from '*'/'Internet' on a port range covering 80 and/or 443."

      if [ "$APPLY" = false ]; then
        echo "  [dry-run] Would prompt to delete this rule."
        continue
      fi

      if confirm_nsg "$name" "$rule_name"; then
        az network nsg rule delete --nsg-name "$name" --resource-group "$rg" --name "$rule_name"
        removed_count=$((removed_count + 1))
        echo "  Deleted rule '$rule_name' on $name."
      else
        echo "  Skipped."
      fi
    fi
  done

  if [ "$found_in_nsg" = false ]; then
    echo "  No overly broad HTTP(S) rules found."
  fi
done

echo
echo "Reviewed $reviewed_count non-ignored NSG(s), flagged $flagged_count rule(s), removed $removed_count."
if [ "$APPLY" = false ] && [ "$flagged_count" -gt 0 ]; then
  echo "Re-run with --apply to remove the flagged rules (with per-NSG confirmation)."
fi
