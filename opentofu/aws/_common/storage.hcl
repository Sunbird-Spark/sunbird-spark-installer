locals {
  # This section will be enabled after final code is pushed and tagged
  # source_base_url = "github.com/<org>/modules.git//app"
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment  = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
  region = local.global_vars.global.cloud_storage_region
  domain = local.global_vars.global.domain
  env = local.global_vars.global.env
}

# For local development
terraform {
  source = "../../modules//storage/"
}

dependency "network" {
    config_path = "../network"
    mock_outputs = {
      vpc_id = "dummy-vpc"
    }
}

inputs = {
  environment    = local.environment
  building_block = local.building_block
  region         = local.region
  domain         = local.domain
  env            = local.env
}