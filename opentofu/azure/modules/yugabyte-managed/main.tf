terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0"
      source  = "hashicorp/azurerm"
    }
    ybm = {
      version = "~> 1.0"
      source  = "yugabyte/ybm"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
  resource_provider_registrations = "none"
}

provider "ybm" {
  host       = var.ybm_host
  auth_token = var.ybm_auth_token
}

locals {
  cluster_name       = "${var.environment}-managed-yugabyte"
  security_principal = var.security_principal != "" ? var.security_principal : var.subscription_id
  pse_host_prefix    = split(".", ybm_private_service_endpoint.this.host)[0]
}

# Yugabyte's own VPC for this cluster (separate from, and linked to, the AKS VNet via Private Link).
resource "ybm_vpc" "this" {
  name  = "${var.environment}-vpc"
  cloud = "AZURE"
  region_cidr_info = [
    {
      region = var.yugabyte_region
      # CIDR is auto-assigned by Aeon for Azure.
    }
  ]
}

# RF3 / AZ-level fault tolerance, matching the current self-hosted 3-master+3-tserver topology.
resource "ybm_cluster" "this" {
  cluster_name = local.cluster_name
  cloud_type   = "AZURE"
  cluster_type = "SYNCHRONOUS"
  cluster_tier = "PAID" # Dedicated (not Sandbox). The Standard/Professional/Enterprise plan tier
  # itself is an account-level billing choice (Usage & Billing > Plan in the
  # console), not a per-cluster Terraform setting.
  fault_tolerance = "ZONE"

  cluster_region_info = [
    {
      region       = var.yugabyte_region
      num_nodes    = var.num_nodes
      vpc_id       = ybm_vpc.this.vpc_id
      num_cores    = var.num_cores
      disk_size_gb = var.disk_size_gb
    }
  ]

  credentials = {
    username = var.db_username
    password = var.db_password
  }

  depends_on = [ybm_vpc.this]
}

# Yugabyte-side half of Azure Private Link.
resource "ybm_private_service_endpoint" "this" {
  cluster_id          = ybm_cluster.this.cluster_id
  region              = var.yugabyte_region
  security_principals = [local.security_principal]
  depends_on          = [ybm_cluster.this]
}

# Azure-side half of Azure Private Link: lands a private IP inside the existing AKS VNet.
resource "azurerm_private_endpoint" "yugabyte" {
  name                = "${var.environment}-yugabyte-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.aks_subnet_id

  private_service_connection {
    name                              = "${var.environment}-yugabyte-psc"
    private_connection_resource_alias = ybm_private_service_endpoint.this.service_name
    is_manual_connection              = true
    request_message                   = "Private Link request from ${var.environment} AKS VNet"
  }
}

resource "azurerm_private_dns_zone" "yugabyte" {
  name                = "azure.yugabyte.cloud"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "yugabyte" {
  name                  = "${var.environment}-yugabyte-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.yugabyte.name
  virtual_network_id    = data.azurerm_virtual_network.aks.id
}

resource "azurerm_private_dns_a_record" "yugabyte" {
  name                = local.pse_host_prefix
  zone_name           = azurerm_private_dns_zone.yugabyte.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.yugabyte.private_service_connection[0].private_ip_address]
}

data "azurerm_virtual_network" "aks" {
  name                = var.aks_vnet_name
  resource_group_name = var.resource_group_name
}
