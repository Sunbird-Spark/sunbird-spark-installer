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

# Anonymous read for blobs, scoped to this one container only ("blob" access type
# grants GET on blobs here, not container listing, and not the parent account's other
# containers). DIAL QR-code-to-content mappings need to be publicly readable by
# anonymous scanners -- this is CDN-style public content delivery, not a blanket
# account-level anonymous-access allowance. Same reasoning as the public buckets in
# opentofu/gcp/modules/storage/main.tf, and writes still require the
# workload-identity-scoped role assignment below, not anonymous access.
resource "azurerm_storage_container" "dial_state_container_public" {
  name                  = "${local.environment_name}-dial-${local.unique_uuid}"
  storage_account_name  = data.azurerm_storage_account.existing.name
  container_access_type = "blob"
}

# Recreated here (was previously defined in modules/workload-identity/main.tf,
# removed as unused dead code by b606a2e when this addon had no consumer yet
# -- f2a2e94 then added dial_container_access below referencing it by name,
# without noticing it no longer existed anywhere). Scoped to just this one
# container, not the whole storage account, since that's the only place this
# addon needs write access.
resource "azurerm_role_definition" "dial_blob_operator_least_privilege" {
  name        = "${local.environment_name}-dial-blob-operator-least-privilege"
  scope       = "${data.azurerm_storage_account.existing.id}/blobServices/default/containers/${azurerm_storage_container.dial_state_container_public.name}"
  description = "Custom role for blob operations with least privilege - read, write, delete, move blobs. Cannot create/delete/manage containers."

  assignable_scopes = ["${data.azurerm_storage_account.existing.id}/blobServices/default/containers/${azurerm_storage_container.dial_state_container_public.name}"]

  permissions {
    actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/read",
    ]

    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/move/action",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
    ]
  }
}

resource "azurerm_role_assignment" "dial_container_access" {
  principal_id         = var.workload_identity_principal_id
  scope                = "${data.azurerm_storage_account.existing.id}/blobServices/default/containers/${azurerm_storage_container.dial_state_container_public.name}"
  role_definition_name = azurerm_role_definition.dial_blob_operator_least_privilege.name
}

resource "null_resource" "update_global_values" {
  triggers = {
    container_name = azurerm_storage_container.dial_state_container_public.name
  }

  provisioner "local-exec" {
    command = "[ -f ${var.global_cloud_values_file} ] || echo 'global: {}' > ${var.global_cloud_values_file}; yq -i '.global.dial_state_container_public = \"${azurerm_storage_container.dial_state_container_public.name}\"' ${var.global_cloud_values_file}"
  }
}
