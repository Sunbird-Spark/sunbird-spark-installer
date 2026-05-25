locals {
  global_vars         = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars          = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {global: {cloud_storage_access_key: "dummy", public_container_name: "dummy", private_container_name: "dummy", velero_storage_container_private: "dummy"}})
  skip_storage_module = local.global_vars.global.skip_storage_module
  environment         = local.global_vars.global.environment
  building_block      = local.global_vars.global.building_block
  subscription_id     = local.global_vars.global.subscription_id
  location            = local.global_vars.global.cloud_storage_region
}

terraform {
  source = "../../modules//workload-identity/"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    resource_group_name = "dummy-rg"
  }
}

dependency "aks" {
  config_path = "../aks"
  mock_outputs = {
    oidc_issuer_url        = "https://dummy-oidc.eastus.cloudapp.azure.com/"
    kubernetes_host        = "https://dummy.hcp.eastus.azmk8s.io:443"
    client_certificate     = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t..."
    client_key             = "LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVkt..."
    cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t..."
  }
}

dependency "storage" {
  config_path  = "../storage"
  skip_outputs = local.skip_storage_module
  mock_outputs = {
    azurerm_storage_account_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dummy-rg/providers/Microsoft.Storage/storageAccounts/dummy"
    azurerm_storage_container_public    = "dummy-public"
    azurerm_storage_container_private   = "dummy-private"
    azurerm_velero_container_name       = "dummy-velero"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  environment                        = local.environment
  building_block                     = local.building_block
  subscription_id                    = local.subscription_id
  location                           = local.location
  resource_group_name                = dependency.network.outputs.resource_group_name
  oidc_issuer_url                    = dependency.aks.outputs.oidc_issuer_url
  storage_account_id                 = local.skip_storage_module ? "/subscriptions/${local.subscription_id}/resourceGroups/${dependency.network.outputs.resource_group_name}/providers/Microsoft.Storage/storageAccounts/${local.cloud_vars.global.cloud_storage_access_key}" : dependency.storage.outputs.azurerm_storage_account_resource_id
  kubernetes_host                    = dependency.aks.outputs.kubernetes_host
  kubernetes_client_certificate      = dependency.aks.outputs.client_certificate
  kubernetes_client_key              = dependency.aks.outputs.client_key
  kubernetes_cluster_ca_certificate  = dependency.aks.outputs.cluster_ca_certificate
  container_names = local.skip_storage_module ? [
    local.cloud_vars.global.public_container_name,
    local.cloud_vars.global.private_container_name,
    local.cloud_vars.global.velero_storage_container_private,
  ] : [
    dependency.storage.outputs.azurerm_storage_container_public,
    dependency.storage.outputs.azurerm_storage_container_private,
    dependency.storage.outputs.azurerm_velero_container_name,
  ]
}
