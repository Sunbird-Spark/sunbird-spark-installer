 terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0"
      source  = "hashicorp/azurerm"
    }
  }
}
provider "azurerm" {
  subscription_id ="${var.subscription_id}"
  features {}  # Always include the features block for Azure provider
  resource_provider_registrations = "none"
  }
data "azurerm_subscription" "current" {}

locals {
    common_tags = {
      environment = "${var.environment}"
      BuildingBlock = "${var.building_block}"
    }
    subid = split("-", "${data.azurerm_subscription.current.subscription_id}")
    environment_name = "${var.building_block}-${var.environment}"
    resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "${local.environment_name}-aks"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.aks_subnet_cidr
  service_endpoints    = var.aks_subnet_service_endpoints
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${local.environment_name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  address_space       = var.vnet_cidr
  tags = merge(
      local.common_tags,
      var.additional_tags
      )
}