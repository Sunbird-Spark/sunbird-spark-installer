locals {
  global_vars     = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  env             = local.global_vars.global.env
  environment     = local.global_vars.global.environment
  building_block  = local.global_vars.global.building_block
  subscription_id = local.global_vars.global.subscription_id
  location        = local.global_vars.global.cloud_storage_region
  service_account_name = try(local.global_vars.global.service_account_name, "azure-workload-sa")
}

terraform {
  source = "../../modules//content-service-identity/"
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    azurerm_storage_account_id = "dummy-storage-account-id"
  }
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
    oidc_issuer_url = "dummy-oidc-issuer-url"
  }
}

inputs = {
  subscription_id        = local.subscription_id
  resource_group_name    = dependency.network.outputs.resource_group_name
  location               = local.location
  building_block         = local.building_block
  environment            = local.environment
  storage_account_id     = dependency.storage.outputs.azurerm_storage_account_id
  oidc_issuer_url        = dependency.aks.outputs.oidc_issuer_url
  kubernetes_namespace   = "sunbird"
  service_account_name   = local.service_account_name
}

