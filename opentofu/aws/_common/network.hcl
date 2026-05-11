locals {
  # Load YAML file instead of environment.hcl
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment  = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
  region = local.global_vars.global.cloud_storage_region
  vpc_cidr_block = try(local.global_vars.global.vpc_cidr_block, "10.0.0.0/16")
}

# For local development
terraform {
  source = "../../modules//network/"
}

inputs = {
  environment    = local.environment
  building_block = local.building_block
  region          = local.region
  vpc_cidr_block = local.vpc_cidr_block
}
