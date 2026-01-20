terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0.1"
      source  = "hashicorp/azurerm"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
  resource_provider_registrations = "none"
}



locals {
  environment_name = "${var.building_block}-${var.environment}"
}

# Create Managed Identity for Content Service
resource "azurerm_user_assigned_identity" "content_service" {
  name                = "${local.environment_name}-content-service-mi"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = {
    Environment = var.environment
    Service     = "content-service"
    ManagedBy   = "terraform"
  }
}

# Assign Storage Blob Data Contributor role to the managed identity
resource "azurerm_role_assignment" "content_service_storage" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.content_service.principal_id

  depends_on = [azurerm_user_assigned_identity.content_service]
}

# Create Federated Identity Credential for Kubernetes ServiceAccount
# The ServiceAccount will be created by Helm with the managed identity annotations
resource "azurerm_federated_identity_credential" "content_service" {
  name                = "${local.environment_name}-content-service-federated-credential"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.content_service.id
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.kubernetes_namespace}:${var.service_account_name}"
  audience            = ["api://AzureADTokenExchange"]

  depends_on = [azurerm_user_assigned_identity.content_service]
}


