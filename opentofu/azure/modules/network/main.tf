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

# skip_network_module = true:  reuse existing VNet/subnets via data sources (names from var.vnet_name etc.)
# skip_network_module = false: OpenTofu creates VNet/subnets via resource blocks

data "azurerm_virtual_network" "vnet" {
  count               = var.skip_network_module ? 1 : 0
  name                = var.vnet_name
  resource_group_name = local.resource_group_name
}

data "azurerm_subnet" "aks_subnet" {
  count                = var.skip_network_module ? 1 : 0
  name                 = var.aks_subnet_name
  resource_group_name  = local.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.vnet[0].name
}

data "azurerm_subnet" "runner_subnet" {
  count                = var.skip_network_module ? 1 : 0
  name                 = var.runner_subnet_name
  resource_group_name  = local.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.vnet[0].name
}

resource "azurerm_virtual_network" "vnet" {
  count               = var.skip_network_module ? 0 : 1
  name                = "${local.environment_name}"
  location            = var.location
  resource_group_name = local.resource_group_name
  address_space       = ["10.0.0.0/16"]
  tags                = merge(local.common_tags, var.additional_tags)
}

resource "azurerm_subnet" "aks_subnet" {
  count                = var.skip_network_module ? 0 : 1
  name                 = "${local.environment_name}-aks"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.0.0.0/20"]
  service_endpoints    = ["Microsoft.Sql", "Microsoft.Storage"]
}

resource "azurerm_subnet" "runner_subnet" {
  count                = var.skip_network_module ? 0 : 1
  name                 = "${local.environment_name}-runner"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.0.16.0/28"]
}
