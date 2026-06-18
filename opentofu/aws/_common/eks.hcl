locals {
  global_vars    = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment    = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
  region         = local.global_vars.global.cloud_storage_region
  eks_version    = try(local.global_vars.global.eks_version, null)
  subnet_ids     = try(local.global_vars.global.subnet_ids, [])
}

# For local development
terraform {
  source = "../../modules//eks/"
}

inputs = {
  environment    = local.environment
  building_block = local.building_block
  region         = local.region
  eks_version    = local.eks_version
  subnet_ids     = local.subnet_ids
}
