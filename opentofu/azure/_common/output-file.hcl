locals {
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  _cloud_defaults = {cloud_storage_access_key: "", public_container_name: "", private_container_name: "", velero_storage_container_private: "", sunbird_encryption_key: ""}
  _cloud_raw      = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {})
  cloud_vars      = {global: merge(local._cloud_defaults, try(local._cloud_raw.global, {}))}
  env                    = local.global_vars.global.env
  environment            = local.global_vars.global.environment
  building_block         = local.global_vars.global.building_block
  subscription_id        = local.global_vars.global.subscription_id
  cloud_storage_provider = local.global_vars.global.cloud_storage_provider
  storage_account_name      = local.cloud_vars.global.cloud_storage_access_key
  storage_container_public  = local.cloud_vars.global.public_container_name
  storage_container_private = local.cloud_vars.global.private_container_name
  velero_container_name     = local.cloud_vars.global.velero_storage_container_private
  sunbird_encryption_key    = local.cloud_vars.global.sunbird_encryption_key
}

# For local development
terraform {
  source = "../../modules//output-file/"
}

dependency "aks" {
    config_path = "../aks"
}

dependency "storage" {
    config_path = "../storage"
    mock_outputs = {
      azurerm_storage_account_name      = "dummy-storage"
      azurerm_storage_container_private = "dummy-private"
      azurerm_storage_container_public  = "dummy-public"
      azurerm_velero_container_name     = "dummy-velero"
    }
    mock_outputs_allowed_terraform_commands = ["init", "plan", "apply", "validate", "output"]
    mock_outputs_merge_strategy_with_state  = "shallow"
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
  storage_account_name               = coalesce(local.storage_account_name, dependency.storage.outputs.azurerm_storage_account_name)
  storage_container_public           = coalesce(local.storage_container_public, dependency.storage.outputs.azurerm_storage_container_public)
  storage_container_private          = coalesce(local.storage_container_private, dependency.storage.outputs.azurerm_storage_container_private)
  random_string                      = dependency.keys.outputs.random_string
  velero_container_name              = coalesce(local.velero_container_name, dependency.storage.outputs.azurerm_velero_container_name)
  cloud_storage_provider             = local.cloud_storage_provider
  azure_client_id                    = dependency.workload_identity.outputs.client_id
  k8s_service_account_name           = "azure-managed-identity-sa"
  sunbird_encryption_key             = local.sunbird_encryption_key
}
