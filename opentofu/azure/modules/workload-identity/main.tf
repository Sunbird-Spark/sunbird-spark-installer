terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0"
      source  = "hashicorp/azurerm"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "kubernetes" {
  host                   = var.kubernetes_host
  client_certificate     = base64decode(var.kubernetes_client_certificate)
  client_key             = base64decode(var.kubernetes_client_key)
  cluster_ca_certificate = base64decode(var.kubernetes_cluster_ca_certificate)
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

resource "kubernetes_service_account" "workload_identity" {
  metadata {
    name      = var.k8s_service_account_name
    namespace = var.k8s_namespace
    labels = {
      "azure.workload.identity/use" = "true"
    }
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.workload_identity.client_id
    }
  }

  depends_on = [
    azurerm_user_assigned_identity.workload_identity,
    azurerm_federated_identity_credential.workload_identity
  ]
}
