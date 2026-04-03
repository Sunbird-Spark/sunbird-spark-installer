locals {
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars   = yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml"))
  environment  = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
  storage_account_name      = local.cloud_vars.global.cloud_storage_access_key
  storage_container_public  = local.cloud_vars.global.public_container_name
  storage_container_private = local.cloud_vars.global.private_container_name
}

# For local development
terraform {
  source = "../../modules//keys/"
}

dependency "workload_identity" {
  config_path = "../workload-identity"
  mock_outputs = {
    deployer_role_ready = "mock"
  }
}

inputs = {
  environment                        = local.environment
  building_block                     = local.building_block
  storage_account_name               = local.storage_account_name
  storage_container_public           = local.storage_container_public
  storage_container_private          = local.storage_container_private
  # random_string                    = local.random_string
}
