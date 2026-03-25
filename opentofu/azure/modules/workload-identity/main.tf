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

data "azurerm_client_config" "current" {}

locals {
  environment_name = "${var.building_block}-${var.environment}"
}

resource "kubernetes_namespace" "namespaces" {
  for_each = toset(var.k8s_namespaces)

  metadata {
    name = each.value
  }
}

resource "azurerm_user_assigned_identity" "workload_identity" {
  name                = "${local.environment_name}-workload-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_federated_identity_credential" "workload_identity" {
  for_each = var.k8s_service_accounts

  name                = "${local.environment_name}-${each.key}-federated-cred"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.workload_identity.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.name}"
}

resource "azurerm_role_definition" "blob_operator_least_privilege" {
  name        = "${local.environment_name}-blob-operator-least-privilege"
  scope       = var.storage_account_id
  description = "Custom role for blob operations with least privilege - read, write, delete, move blobs and generate user delegation keys. Cannot create/delete/manage containers."

  assignable_scopes = [var.storage_account_id]

  permissions {
    actions = []

    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/move/action",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
      "Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action"
    ]
  }
}

resource "azurerm_role_assignment" "workload_identity_blob_operator" {
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  scope                = var.storage_account_id
  role_definition_id   = azurerm_role_definition.blob_operator_least_privilege.role_definition_resource_id

  depends_on = [
    azurerm_user_assigned_identity.workload_identity,
    azurerm_role_definition.blob_operator_least_privilege
  ]
}

resource "kubernetes_service_account" "workload_identity" {
  for_each = var.k8s_service_accounts

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
    labels = {
      "azure.workload.identity/use" = "true"
    }
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.workload_identity.client_id
    }
  }

  depends_on = [
    kubernetes_namespace.namespaces,
    azurerm_user_assigned_identity.workload_identity,
    azurerm_federated_identity_credential.workload_identity
  ]
}
