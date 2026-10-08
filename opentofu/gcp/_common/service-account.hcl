locals {
  # Load YAML file instead of environment.hcl
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment  = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
  project = local.global_vars.global.cloud_storage_project
}

# For local development
terraform {
  source = "../../modules//service-account/"
}

dependency "storage" {
    config_path = "../storage"
    mock_outputs = {
      gcp_private_container_name           = "dummy"
      gcp_public_container_name            = "dummy"
      gcp_dial_state_container_public      = "dummy"
      gcp_velero_storage_container_private = "dummy"
    }
}

inputs = {
  environment         = local.environment
  building_block      = local.building_block
  project             = local.project
  sa_key_store_bucket = dependency.storage.outputs.gcp_private_container_name
  public_bucket       = dependency.storage.outputs.gcp_public_container_name
  dial_state_bucket   = dependency.storage.outputs.gcp_dial_state_container_public
  velero_bucket       = dependency.storage.outputs.gcp_velero_storage_container_private
}