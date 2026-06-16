locals {
  # This section will be enabled after final code is pushed and tagged
  # source_base_url = "github.com/<org>/modules.git//app"
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment  = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
  region = local.global_vars.global.cloud_storage_region
  # random_string  = local.environment_vars.locals.random_string 
}

# For local development
terraform {
  source = "../../modules//eks/"
}

dependency "network" {
    config_path = "../network"
    mock_outputs = {
      vpc_id = "dummy-vpc"
      public_subnet_ids = ["dummy-subnet-pub"]
      private_subnet_ids = ["dummy-subnet-priv"]
    }
}

inputs = {
  environment                = local.environment
  building_block             = local.building_block
  region                     = local.region
  vpc_id                     = dependency.network.outputs.vpc_id
  public_subnet_ids          = dependency.network.outputs.public_subnet_ids
  private_subnet_ids         = dependency.network.outputs.private_subnet_ids
}