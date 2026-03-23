locals {
  global_vars     = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment     = local.global_vars.global.environment
  building_block  = local.global_vars.global.building_block
  subscription_id = local.global_vars.global.subscription_id
  location        = local.global_vars.global.cloud_storage_region
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
    oidc_issuer_url = "https://dummy-oidc.eastus.cloudapp.azure.com/"
  }
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    azurerm_storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dummy-rg/providers/Microsoft.Storage/storageAccounts/dummy"
  }
}

inputs = {
  environment              = local.environment
  building_block           = local.building_block
  subscription_id          = local.subscription_id
  location                 = local.location
  resource_group_name      = dependency.network.outputs.resource_group_name
  oidc_issuer_url          = dependency.aks.outputs.oidc_issuer_url
  storage_account_id       = dependency.storage.outputs.azurerm_storage_account_id
  k8s_namespace            = "sunbird"
  k8s_service_account_name = "workload-identity"
}
