locals {
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars   = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {global: {cloud_storage_access_key: "", cloud_storage_secret_key: "", public_container_name: "", private_container_name: "", velero_storage_container_private: ""}})
  env                    = local.global_vars.global.env
  environment            = local.global_vars.global.environment
  building_block         = local.global_vars.global.building_block
  subscription_id        = local.global_vars.global.subscription_id
  cloud_storage_provider = local.global_vars.global.cloud_storage_provider
  storage_account_name      = local.cloud_vars.global.cloud_storage_access_key
  storage_account_key       = local.cloud_vars.global.cloud_storage_secret_key
  storage_container_public  = local.cloud_vars.global.public_container_name
  storage_container_private = local.cloud_vars.global.private_container_name
  velero_container_name     = local.cloud_vars.global.velero_storage_container_private
}

# For local development
terraform {
  source = "../../modules//output-file/"
}

dependency "aks" {
    config_path = "../aks"
}

dependency "workload_identity" {
    config_path = "../workload-identity"
    mock_outputs = {
      client_id = "00000000-0000-0000-0000-000000000000"
    }
    mock_outputs_allowed_terraform_commands = ["init", "plan", "apply", "validate", "output"]
    mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "keys" {
    config_path = "../keys"
    mock_outputs = {
      random_string     = "dummy-string"
    }
    mock_outputs_allowed_terraform_commands = ["init", "plan", "apply", "validate", "output"]
}


inputs = {
  env                                = local.env
  environment                        = local.environment
  building_block                     = local.building_block
  subscription_id                    = local.subscription_id
  private_ingressgateway_ip          = dependency.aks.outputs.private_ingressgateway_ip
  storage_account_name               = local.storage_account_name
  storage_container_public           = local.storage_container_public
  storage_container_private          = local.storage_container_private
  storage_account_primary_access_key = local.storage_account_key
  random_string                      = dependency.keys.outputs.random_string
  velero_container_name              = local.velero_container_name
  cloud_storage_provider             = local.cloud_storage_provider
  azure_client_id                    = dependency.workload_identity.outputs.client_id
  k8s_service_account_name           = "azure-managed-identity-sa"
}
