locals {
  # This section will be enabled after final code is pushed and tagged
  # source_base_url = "github.com/<org>/modules.git//app"
  global_vars         = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars          = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {global: {cloud_storage_access_key: "", public_container_name: "", private_container_name: ""}})
  skip_storage_module = local.global_vars.global.skip_storage_module
  environment         = local.global_vars.global.environment
  building_block      = local.global_vars.global.building_block
  # random_string  = local.environment_vars.locals.random_string
}

# For local development
terraform {
  source = "../../modules//keys/"
}

dependency "storage" {
    config_path  = "../storage"
    skip_outputs = local.skip_storage_module
    mock_outputs = {
      azurerm_storage_account_name      = "dummy-account"
      azurerm_storage_container_public  = "dummy-container-public"
      azurerm_storage_container_private = "dummy-container-private"
    }
    mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  environment               = local.environment
  building_block            = local.building_block
  storage_account_name      = local.skip_storage_module ? local.cloud_vars.global.cloud_storage_access_key : dependency.storage.outputs.azurerm_storage_account_name
  storage_container_public  = local.skip_storage_module ? local.cloud_vars.global.public_container_name : dependency.storage.outputs.azurerm_storage_container_public
  storage_container_private = local.skip_storage_module ? local.cloud_vars.global.private_container_name : dependency.storage.outputs.azurerm_storage_container_private
  # random_string           = local.random_string
}
