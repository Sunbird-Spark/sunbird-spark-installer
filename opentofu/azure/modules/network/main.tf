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

# Azure Bastion — only when vpn_enabled = false
# AzureBastionSubnet is a fixed name required by Azure; /26 minimum
locals {
  active_vnet_name = var.skip_network_module ? data.azurerm_virtual_network.vnet[0].name : azurerm_virtual_network.vnet[0].name
}

resource "azurerm_subnet" "bastion_subnet" {
  count                = var.vpn_enabled ? 0 : 1
  name                 = "AzureBastionSubnet"
  resource_group_name  = local.resource_group_name
  virtual_network_name = local.active_vnet_name
  address_prefixes     = ["10.0.17.0/26"]
}

resource "azurerm_public_ip" "bastion_pip" {
  count               = var.vpn_enabled ? 0 : 1
  name                = "${local.environment_name}-bastion-pip"
  location            = var.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(local.common_tags, var.additional_tags)
}

resource "azurerm_bastion_host" "bastion" {
  count               = var.vpn_enabled ? 0 : 1
  name                = "${local.environment_name}-bastion"
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "Basic"

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion_subnet[0].id
    public_ip_address_id = azurerm_public_ip.bastion_pip[0].id
  }

  tags = merge(local.common_tags, var.additional_tags)
}
