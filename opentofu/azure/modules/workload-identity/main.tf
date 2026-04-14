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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
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
  description = "Custom role for blob operations with least privilege - read, write, delete, move blobs. Cannot create/delete/manage containers."

  assignable_scopes = [var.storage_account_id]

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

# Container-level role assignments for least-privilege access
# Managed identity can only access specified containers
resource "azurerm_role_assignment" "workload_identity_containers" {
  for_each = toset(var.container_names)

  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  scope                = "${var.storage_account_id}/blobServices/default/containers/${each.value}"
  role_definition_id   = azurerm_role_definition.blob_operator_least_privilege.role_definition_resource_id
}

# Blob data plane access for the deployer identity running tofu apply.
# Owner/Contributor roles only cover control plane — az storage --auth-mode login
# requires an explicit Storage Blob Data role on the data plane.
resource "azurerm_role_assignment" "deployer_blob_containers" {
  for_each = toset(var.container_names)

  principal_id         = data.azurerm_client_config.current.object_id
  scope                = "${var.storage_account_id}/blobServices/default/containers/${each.value}"
  role_definition_id   = azurerm_role_definition.blob_operator_least_privilege.role_definition_resource_id
}

# Azure role assignments take time to propagate across the control plane.
# Downstream modules (keys, upload-files) depend on this sleep via workload-identity
# dependency so they never run before the roles are active.
resource "time_sleep" "wait_for_deployer_role_propagation" {
  create_duration = "60s"
  depends_on      = [azurerm_role_assignment.deployer_blob_containers]
}

# Check if the DIAL container exists in Azure by querying the storage account directly.
# The dial addon names its container: ${building_block}-${environment}-dial-${uuid}
# If the container exists, assign the role; if not, skip without error.
data "external" "dial_container" {
  program = [
    "bash", "-c",
    "result=$(az storage container list --account-name ${local.storage_account_name} --auth-mode login --query \"[?contains(name, '${local.environment_name}-dial-')].name | [0]\" --output tsv 2>/dev/null || echo ''); echo \"{\\\"name\\\": \\\"$${result:-}\\\"}\""
  ]
}

resource "azurerm_role_assignment" "workload_identity_dial_container" {
  count = data.external.dial_container.result["name"] != "" ? 1 : 0

  principal_id         = azurerm_user_assigned_identity.workload_identity.principal_id
  scope                = "${var.storage_account_id}/blobServices/default/containers/${data.external.dial_container.result["name"]}"
  role_definition_id   = azurerm_role_definition.blob_operator_least_privilege.role_definition_resource_id
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
    azurerm_federated_identity_credential.workload_identity
  ]
}
