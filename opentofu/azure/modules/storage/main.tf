terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0"
      source  = "hashicorp/azurerm"
    }
  }
}
provider "azurerm" {
  subscription_id = var.subscription_id
  features {}                              # Always include the features block for Azure provider
  resource_provider_registrations = "none" # Optional
  storage_use_azuread             = true
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
}

resource "azurerm_storage_account" "storage_account" {
  name                       = local.storage_account_name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  account_tier               = var.azure_storage_tier
  account_replication_type   = var.azure_storage_replication
  https_traffic_only_enabled = true
  shared_access_key_enabled  = false

  # System-assigned identity for the storage account resource itself (e.g. if this
  # account later adopts customer-managed keys via Key Vault, or diagnostic settings
  # that need to authenticate outward). This is separate from, and doesn't conflict
  # with, modules/workload-identity's user-assigned identity -- that one is used by
  # Kubernetes workloads/Terraform to authenticate INTO this account (RBAC roles
  # scoped to azurerm_storage_account.storage_account.id); shared_access_key_enabled
  # = false + storage_use_azuread above already make that the only way in.
  identity {
    type = "SystemAssigned"
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }

    cors_rule {
      max_age_in_seconds = 200
      allowed_origins    = ["*"]
      allowed_methods    = ["GET", "HEAD", "OPTIONS", "PUT"]
      exposed_headers    = ["Access-Control-Allow-Origin", "Access-Control-Allow-Methods"]
      allowed_headers    = ["Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Origin", "x-ms-meta-qq", "x-ms-blob-type", "x-ms-blob-content-type", "Content-Type"]

    }
  }
  tags = merge(
    local.common_tags,
    var.additional_tags
  )
}

resource "azurerm_storage_container" "storage_container_private" {
  name                  = "${local.environment_name}-private-${local.unique_uuid}"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "velero_storage_container_private" {
  name                  = "${local.environment_name}-velero-private-${local.unique_uuid}"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "private"
}
# Anonymous read for blobs, scoped to this one container only ("blob" access type
# grants GET on blobs in this container, not container listing, and not the account's
# other containers -- storage_container_private and velero_storage_container_private
# above stay "private"). This is CDN-style public content delivery, not a blanket
# account-level anonymous-access allowance -- same reasoning as the public buckets in
# opentofu/gcp/modules/storage/main.tf.
resource "azurerm_storage_container" "storage_container_public" {
  name                  = "${local.environment_name}-public-${local.unique_uuid}"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "blob"
}

