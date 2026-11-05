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

# NOTE (skip_network_module = true / BYO VNet): these subnets are read via
# data source only — Terraform can't add service endpoints to a subnet it
# doesn't manage. The Key Vault firewall (keys module) allow-lists these
# subnets by ID, but that only works if Microsoft.KeyVault is already
# enabled on them. Enable it manually on the reused subnets before applying.
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
  # Microsoft.KeyVault is required for the keys module's Key Vault firewall
  # (network_acls) to actually let this subnet through — allow-listing a
  # subnet ID there does nothing if the subnet itself lacks the matching
  # service endpoint; Azure silently drops the traffic instead.
  service_endpoints = ["Microsoft.Sql", "Microsoft.Storage", "Microsoft.KeyVault"]
}

resource "azurerm_subnet" "runner_subnet" {
  count                = var.skip_network_module ? 0 : 1
  name                 = "${local.environment_name}-runner"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet[0].name
  address_prefixes     = ["10.0.16.0/28"]
  # Same reason as aks_subnet above — the runner VM is the other identity
  # that needs to reach the firewalled Key Vault (it's the one running
  # `tofu apply` and writing secrets into it).
  service_endpoints = ["Microsoft.KeyVault"]
}

# Baseline subnet-level NSG (AZURE_SECURITY_PLAN.md #6) — aks_subnet only.
# Deliberately no custom rules — just Azure's own defaults
# (AllowVnetInBound, AllowAzureLoadBalancerInBound, DenyAllInBound;
# AllowVnetOutBound, AllowInternetOutBound, DenyAllOutBound). AKS nodes have
# no public IPs, so this matches the real traffic pattern already in place —
# it closes the "no NSG at all" gap without hand-writing an AKS
# required-ports allow-list that can't be validated against a live cluster
# here. Only attached when this module creates the subnet
# (skip_network_module = false) — a BYO VNet may already have its own NSG on
# the reused subnet, and a subnet can only have one.
#
# runner_subnet deliberately does NOT get one: when vpn_enabled = true (the
# default), the runner VM has a public IP and its NIC-level NSG
# (setup-installer-vm.sh) explicitly opens UDP 1194 + TCP 443 to the
# internet for the VPN server — that's the only way into this environment.
# Azure's default NSG rules don't include an internet-inbound allow, only
# VirtualNetwork/AzureLoadBalancer; a subnet-level NSG here would sit
# alongside the NIC-level one and silently block that inbound (both must
# allow, and the defaults-only subnet NSG wouldn't), locking out VPN access
# entirely. The NIC-level NSG already scopes this VM correctly on its own.
resource "azurerm_network_security_group" "aks_subnet" {
  count               = var.skip_network_module ? 0 : 1
  name                = "${local.environment_name}-aks-nsg"
  location            = var.location
  resource_group_name = local.resource_group_name
  tags                = merge(local.common_tags, var.additional_tags)
}

resource "azurerm_subnet_network_security_group_association" "aks_subnet" {
  count                     = var.skip_network_module ? 0 : 1
  subnet_id                 = azurerm_subnet.aks_subnet[0].id
  network_security_group_id = azurerm_network_security_group.aks_subnet[0].id
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
