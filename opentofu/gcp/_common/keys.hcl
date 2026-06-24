locals {
  global_vars         = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars          = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {global: {public_container_name: "", private_container_name: ""}})
  skip_storage_module = local.global_vars.global.skip_storage_module
  environment         = local.global_vars.global.environment
  building_block      = local.global_vars.global.building_block
}

# For local development
terraform {
  source = "../../modules//keys/"
}

dependency "storage" {
  config_path  = "../storage"
  skip_outputs = local.skip_storage_module
  mock_outputs = {
    gcp_private_container_name = "dummy-container-private"
    gcp_public_container_name  = "dummy-container-public"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  environment               = local.environment
  building_block            = local.building_block
  storage_container_private = local.skip_storage_module ? local.cloud_vars.global.private_container_name : dependency.storage.outputs.gcp_private_container_name
  storage_container_public  = local.skip_storage_module ? local.cloud_vars.global.public_container_name  : dependency.storage.outputs.gcp_public_container_name
}
