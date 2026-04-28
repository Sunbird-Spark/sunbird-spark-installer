terraform {
  source = "../../modules//upload-files/"
}

locals {
  global_vars         = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars          = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {global: {cloud_storage_access_key: "", public_container_name: ""}})
  skip_storage_module = local.global_vars.global.skip_storage_module
}

dependency "storage" {
    config_path  = "../storage"
    skip_outputs = local.skip_storage_module
    mock_outputs = {
      azurerm_storage_account_name     = "dummy-account"
      azurerm_storage_container_public = "dummy-container-public"
    }
    mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "workload_identity" {
  config_path = "../workload-identity"
}

inputs = {
  storage_account_name     = local.skip_storage_module ? local.cloud_vars.global.cloud_storage_access_key : dependency.storage.outputs.azurerm_storage_account_name
  storage_container_public = local.skip_storage_module ? local.cloud_vars.global.public_container_name : dependency.storage.outputs.azurerm_storage_container_public
}
