terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0"
      source  = "hashicorp/azurerm"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "random_id" "dial_bucket_id" {
  byte_length = 5
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
  resource_provider_registrations = "none"
}

locals {
  unique_uuid      = random_id.dial_bucket_id.hex
  environment_name = "${var.building_block}-${var.environment}"
}

data "azurerm_storage_account" "existing" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_storage_container" "dial_state_container_public" {
  name                  = "${local.environment_name}-dial-${local.unique_uuid}"
  storage_account_name  = data.azurerm_storage_account.existing.name
  container_access_type = "blob"
}

resource "null_resource" "update_global_values" {
  triggers = {
    container_name = azurerm_storage_container.dial_state_container_public.name
  }

  provisioner "local-exec" {
    command = "[ -f ${var.global_cloud_values_file} ] || echo 'global: {}' > ${var.global_cloud_values_file}; yq -i '.global.dial_state_container_public = \"${azurerm_storage_container.dial_state_container_public.name}\"' ${var.global_cloud_values_file}"
  }
}
