terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0.1"
      source  = "hashicorp/azurerm"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
  resource_provider_registrations = "none"
}

data "azurerm_storage_account" "existing" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_storage_container" "dial_state_container_public" {
  name                  = "${var.environment}-dial-${var.unique_uuid}"
  storage_account_name  = data.azurerm_storage_account.existing.name
  container_access_type = "blob"
}

resource "null_resource" "update_global_values" {
  triggers = {
    container_name = azurerm_storage_container.dial_state_container_public.name
  }

  provisioner "local-exec" {
    command = "yq -i '.global.dial_state_container_public = \"${azurerm_storage_container.dial_state_container_public.name}\"' ${path.module}/../../../../global-values.yaml"
  }
}
