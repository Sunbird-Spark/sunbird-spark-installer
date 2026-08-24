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
  client_certificate     = var.kubernetes_client_certificate
  client_key             = var.kubernetes_client_key
  cluster_ca_certificate = var.kubernetes_cluster_ca_certificate
}

data "azurerm_client_config" "current" {}

locals {
  environment_name     = "${var.building_block}-${var.environment}"
  storage_account_name = reverse(split("/", var.storage_account_id))[0]

  # Containers this workload identity actually needs blob data access to,
  # paired with the storage account each one actually lives in. Public
  # lives in var.storage_account_id (unrestricted); private + velero live
  # in var.private_storage_account_id (firewalled to AKS + runner subnets,
  # AZURE_SECURITY_PLAN.md #2). Scoping the role assignment per-container
  # (instead of the whole account) also limits the blast radius of any SAS
  # minted with the generateUserDelegationKey permission below.
  storage_containers = {
    private = { account_id = var.private_storage_account_id, name = var.storage_container_private_name }
    public  = { account_id = var.storage_account_id, name = var.storage_container_public_name }
    velero  = { account_id = var.private_storage_account_id, name = var.storage_container_velero_name }
  }
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

  name      = "${local.environment_name}-${each.key}-federated-cred"
  parent_id = azurerm_user_assigned_identity.workload_identity.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.name}"
}

# Storage account-level role for generating user delegation keys (required for SAS tokens).
# This permission cannot be granted at container scope — it must be at the storage account level.
resource "azurerm_role_definition" "user_delegation_key" {
  name        = "${local.environment_name}-user-delegation-key"
  scope       = var.storage_account_id
  description = "Allows generating user delegation keys for SAS token creation."

  assignable_scopes = [var.storage_account_id]

  permissions {
    actions = [
      "Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action"
    ]

    data_actions = []
  }
}

resource "azurerm_role_assignment" "workload_identity_user_delegation_key" {
  principal_id       = azurerm_user_assigned_identity.workload_identity.principal_id
  scope              = var.storage_account_id
  role_definition_id = azurerm_role_definition.user_delegation_key.role_definition_resource_id
}

# A user delegation SAS can never grant more than the signing principal's
# actual RBAC on the target container — so scoping this per-container (rather
# than at the storage account) is what actually bounds what a SAS minted via
# generateUserDelegationKey (above) can be used for.
resource "azurerm_role_assignment" "workload_identity_storage_blob_contributor" {
  for_each             = local.storage_containers
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  scope                = "${each.value.account_id}/blobServices/default/containers/${each.value.name}"
  role_definition_name = "Storage Blob Data Contributor"
}

# Kept account-scoped deliberately: "Reader" is an ARM management-plane role
# (account properties/endpoint discovery, e.g. for the Velero Azure plugin),
# not a data-plane grant — it does not expose blob content, only resource
# metadata, so the broader scope here is much lower risk than the Blob Data
# Contributor split above. Granted on both accounts since Velero's container
# now lives on the private one.
resource "azurerm_role_assignment" "workload_identity_storage_reader" {
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  scope                = var.storage_account_id
  role_definition_name = "Reader"
}

resource "azurerm_role_assignment" "workload_identity_private_storage_reader" {
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  scope                = var.private_storage_account_id
  role_definition_name = "Reader"
}

# Read-only — pods use this identity to pull secrets via the Key Vault CSI
# driver / SDK. Secret write access stays with whoever runs `tofu apply`
# (granted inside the keys module, scoped to the vault it creates).
resource "azurerm_role_assignment" "workload_identity_key_vault_secrets_user" {
  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
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
    azurerm_user_assigned_identity.workload_identity,
    azurerm_federated_identity_credential.workload_identity,
    kubernetes_namespace.namespaces
  ]
}
