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
    s3_bucket_public  = "dummy-bucket-public"
    s3_bucket_private = "dummy-bucket-private"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  environment            = local.environment
  building_block         = local.building_block
  storage_bucket_public  = local.skip_storage_module ? local.cloud_vars.global.public_container_name : dependency.storage.outputs.s3_bucket_public
  storage_bucket_private = local.skip_storage_module ? local.cloud_vars.global.private_container_name : dependency.storage.outputs.s3_bucket_private
}
