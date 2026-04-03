locals {
  global_vars     = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars      = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {global: {cloud_storage_access_key: "dummy", public_container_name: "dummy", private_container_name: "dummy", velero_storage_container_private: "dummy"}})
  environment     = local.global_vars.global.environment
  building_block  = local.global_vars.global.building_block
  subscription_id = local.global_vars.global.subscription_id
  location        = local.global_vars.global.cloud_storage_region
  storage_account_name      = local.cloud_vars.global.cloud_storage_access_key
  storage_container_public  = local.cloud_vars.global.public_container_name
  storage_container_private = local.cloud_vars.global.private_container_name
  velero_container          = local.cloud_vars.global.velero_storage_container_private
}

terraform {
  source = "../../modules//workload-identity/"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    resource_group_name = "dummy-rg"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply", "validate", "output"]
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
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply", "validate", "output"]
}

inputs = {
  environment                        = local.environment
  building_block                     = local.building_block
  subscription_id                    = local.subscription_id
  location                           = local.location
  resource_group_name                = dependency.network.outputs.resource_group_name
  oidc_issuer_url                    = dependency.aks.outputs.oidc_issuer_url
  storage_account_id                 = "/subscriptions/${local.global_vars.global.subscription_id}/resourceGroups/${get_env("AZURE_OPENTOFU_BACKEND_RG")}/providers/Microsoft.Storage/storageAccounts/${local.storage_account_name}"
  kubernetes_host                    = dependency.aks.outputs.kubernetes_host
  kubernetes_client_certificate      = dependency.aks.outputs.client_certificate
  kubernetes_client_key              = dependency.aks.outputs.client_key
  kubernetes_cluster_ca_certificate  = dependency.aks.outputs.cluster_ca_certificate
  container_names = [
    local.storage_container_public,
    local.storage_container_private,
    local.velero_container,
  ]
}
