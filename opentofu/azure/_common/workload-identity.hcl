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
    oidc_issuer_url             = "https://dummy-oidc.eastus.cloudapp.azure.com/"
    kubernetes_host             = "https://dummy.hcp.eastus.azmk8s.io:443"
    client_certificate          = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t..."
    client_key                  = "LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVkt..."
    cluster_ca_certificate      = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t..."
  }
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    azurerm_storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/dummy-rg/providers/Microsoft.Storage/storageAccounts/dummy"
  }
}

inputs = {
  environment                        = local.environment
  building_block                     = local.building_block
  subscription_id                    = local.subscription_id
  location                           = local.location
  resource_group_name                = dependency.network.outputs.resource_group_name
  oidc_issuer_url                    = dependency.aks.outputs.oidc_issuer_url
  storage_account_id                 = dependency.storage.outputs.azurerm_storage_account_id
  k8s_namespace                      = "sunbird"
  k8s_service_account_name           = "workload-identity"
  kubernetes_host                    = dependency.aks.outputs.kubernetes_host
  kubernetes_client_certificate      = dependency.aks.outputs.client_certificate
  kubernetes_client_key              = dependency.aks.outputs.client_key
  kubernetes_cluster_ca_certificate  = dependency.aks.outputs.cluster_ca_certificate
}
