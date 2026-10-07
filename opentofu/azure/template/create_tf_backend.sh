#!/bin/bash
set -euo pipefail

# Check if the global-values.yaml file exists
if [[ ! -f "global-values.yaml" ]]; then
  echo "Error: global-values.yaml file does not exist!"
  exit 1
fi

# Extract values using yq (YAML processor)
if ! command -v yq &> /dev/null; then
  echo "Error: yq is not installed. Please install yq to process YAML files."
  exit 1
fi

# Read values from global-values.yaml
building_block=$(yq '.global.building_block' global-values.yaml)
environment_name=$(yq '.global.environment' global-values.yaml)
location=$(yq '.global.cloud_storage_region' global-values.yaml)
resource_group_name=$(yq '.global.resource_group_name' global-values.yaml)

# Validate that the values are extracted correctly
if [[ -z "$building_block" || -z "$environment_name" ]]; then
  echo "Error: Unable to extract values from global-values.yaml"
  exit 1
fi

# Debugging: Print extracted values
echo "Extracted building_block: \"$building_block\""
echo "Extracted environment_name: \"$environment_name\""

# Get Azure tenant ID (first segment of the Tenant ID)
ID=$(az account show | jq -r .tenantId | cut -d '-' -f1)

# Get Azure Subscription ID
SUBSCRIPTION_ID=$(az account show | jq -r .id)

# Construct resource names
if [[ -z "$resource_group_name" || "$resource_group_name" == "null" ]]; then
  RESOURCE_GROUP_NAME="${building_block}-${environment_name}"
else
  RESOURCE_GROUP_NAME="$resource_group_name"
fi
STORAGE_ACCOUNT_NAME="${environment_name}tfstate$ID"
CONTAINER_NAME="${environment_name}tfstate"

# Debugging: Print generated names
echo "RESOURCE_GROUP_NAME: $RESOURCE_GROUP_NAME"
echo "STORAGE_ACCOUNT_NAME: $STORAGE_ACCOUNT_NAME"
echo "CONTAINER_NAME: $CONTAINER_NAME"
echo "SUBSCRIPTION_ID: $SUBSCRIPTION_ID"

# Create resource group only if it does not already exist
if az group show --name "$RESOURCE_GROUP_NAME" &>/dev/null; then
  echo "Resource group '$RESOURCE_GROUP_NAME' already exists — skipping creation."
else
  az group create --name "$RESOURCE_GROUP_NAME" --location "$location"
fi

# Create the storage account
az storage account create --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$STORAGE_ACCOUNT_NAME" --sku Standard_LRS --encryption-services blob \
  --min-tls-version TLS1_2 --allow-shared-key-access false

# Create the blob container
az storage container create --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT_NAME" --auth-mode login

# Lock the storage account to this VM's own subnet. This script runs ON the
# installer VM (setup-installer-vm.sh already added Microsoft.Storage to its
# subnet), so that subnet already exists at this point.
VM_RESOURCE_ID=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01" 2>/dev/null | jq -r '.resourceId // empty')
if [ -n "$VM_RESOURCE_ID" ]; then
  NIC_ID=$(az vm show --ids "$VM_RESOURCE_ID" --query "networkProfile.networkInterfaces[0].id" -o tsv)
  SUBNET_ID=$(az network nic show --ids "$NIC_ID" --query "ipConfigurations[0].subnet.id" -o tsv)
  SUBNET_NAME=$(echo "$SUBNET_ID" | awk -F'/' '{print $NF}')

  az storage account network-rule add --account-name "$STORAGE_ACCOUNT_NAME" --subnet "$SUBNET_ID"
  az storage account update --name "$STORAGE_ACCOUNT_NAME" --default-action Deny
  echo "✓ Storage account $STORAGE_ACCOUNT_NAME locked to VM's subnet: $SUBNET_NAME"
else
  echo "⚠ Not running on an Azure VM (no instance metadata) — storage account network left open."
fi

# Export OpenTofu backend details to a file
echo "export AZURE_OPENTOFU_BACKEND_RG=$RESOURCE_GROUP_NAME" > tf.sh
echo "export AZURE_OPENTOFU_BACKEND_STORAGE_ACCOUNT=$STORAGE_ACCOUNT_NAME" >> tf.sh
echo "export AZURE_OPENTOFU_BACKEND_CONTAINER=$CONTAINER_NAME" >> tf.sh
echo "export AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID" >> tf.sh  # <-- Added Subscription ID export

echo -e "\nOpenTofu backend setup complete!"
echo -e "Run the following command to set the environment variables:"
echo "source tf.sh"
