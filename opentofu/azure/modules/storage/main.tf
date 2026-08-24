terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0"
      source  = "hashicorp/azurerm"
    }
  }
}
provider "azurerm" {
  subscription_id                 = var.subscription_id
  features {}                              # Always include the features block for Azure provider
  resource_provider_registrations = "none" # Optional
  storage_use_azuread              = true
}
data "azurerm_subscription" "current" {}

resource "random_id" "bucket_id" {
  byte_length = 5
}

locals {
  unique_uuid = random_id.bucket_id.hex

  common_tags = {
    environment   = "${var.environment}"
    BuildingBlock = "${var.building_block}"
    unique_uuid   = local.unique_uuid
  }
  subid                           = split("-", "${data.azurerm_subscription.current.subscription_id}")
  environment_name                = "${var.building_block}-${var.environment}"
  uid                             = local.subid[0]
  environment_name_without_dashes = replace(local.environment_name, "-", "")
  storage_account_name            = "${local.environment_name_without_dashes}${local.uid}"
  # Storage account names are capped at 24 chars — truncate before adding
  # the suffix rather than assuming the base always leaves room.
  private_storage_account_name = substr("${local.storage_account_name}priv", 0, 24)
}

# Public content only (AZURE_SECURITY_PLAN.md #2 / #7). No network firewall
# here — this is the account real end users' browsers hit directly for
# anonymous reads, and it's also where knowlg's upload-url endpoint sends
# content creators to PUT files via a signed URL from arbitrary internet
# IPs. Either of those breaks under an account-level firewall. Soft delete +
# versioning (below) is the recovery layer instead of a network restriction.
resource "azurerm_storage_account" "storage_account" {
  name                       = local.storage_account_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  account_tier               = var.azure_storage_tier
  account_replication_type   = var.azure_storage_replication
  https_traffic_only_enabled = true
  shared_access_key_enabled  = false
  blob_properties {
    cors_rule {
      max_age_in_seconds = 200
      allowed_origins    = ["*"]
      allowed_methods    = ["GET", "HEAD", "OPTIONS", "PUT"]
      exposed_headers    = ["Access-Control-Allow-Origin", "Access-Control-Allow-Methods"]
      allowed_headers    = ["Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Origin", "x-ms-meta-qq", "x-ms-blob-type", "x-ms-blob-content-type", "Content-Type"]

    }

    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
  tags = merge(
    local.common_tags,
    var.additional_tags
  )
}

resource "azurerm_storage_container" "storage_container_public" {
  name                  = "${local.environment_name}-public-${local.unique_uuid}"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "blob"
}

# Private + Velero containers only. Nothing external ever touches these
# directly — cert/flink/secor/nlwebflink read and write them from inside AKS
# via the workload identity's AAD auth (no SAS is ever minted against these
# containers, unlike the public one — verified against every chart that
# references private_container_name/velero_storage_container_private), and
# Velero's own plugin runs inside the cluster too. So unlike the public
# account, firewalling this one to just the AKS + runner subnets doesn't
# break any real access pattern.
resource "azurerm_storage_account" "private_storage_account" {
  name                       = local.private_storage_account_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  account_tier               = var.azure_storage_tier
  account_replication_type   = var.azure_storage_replication
  https_traffic_only_enabled = true
  shared_access_key_enabled  = false

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [var.aks_subnet_id, var.runner_subnet_id]
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = merge(
    local.common_tags,
    var.additional_tags
  )
}

resource "azurerm_storage_container" "storage_container_private" {
  name                  = "${local.environment_name}-private-${local.unique_uuid}"
  storage_account_name  = azurerm_storage_account.private_storage_account.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "velero_storage_container_private" {
  name                  = "${local.environment_name}-velero-private-${local.unique_uuid}"
  storage_account_name  = azurerm_storage_account.private_storage_account.name
  container_access_type = "private"
}
