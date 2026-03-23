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
  features {}
}

locals {
  environment_name = "${var.building_block}-${var.environment}"
}

resource "azurerm_user_assigned_identity" "workload_identity" {
  name                = "${local.environment_name}-workload-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_federated_identity_credential" "workload_identity" {
  name                = "${local.environment_name}-workload-identity-federated-cred"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.workload_identity.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"
}

resource "azurerm_role_assignment" "workload_identity_storage_blob_contributor" {
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"

  depends_on = [azurerm_user_assigned_identity.workload_identity]
}
