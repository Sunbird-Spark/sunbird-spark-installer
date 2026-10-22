locals {
  global_vars         = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment         = local.global_vars.global.environment
  building_block      = local.global_vars.global.building_block
  region              = local.global_vars.global.cloud_storage_region
  eks_version         = try(local.global_vars.global.eks_version, null)
  manual_subnet_ids   = try(local.global_vars.global.subnet_ids, [])
  skip_network_module = try(local.global_vars.global.skip_network_module, true)
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    private_subnet_ids = []
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy", "init", "output"]
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
  subnet_ids     = local.skip_network_module ? local.manual_subnet_ids : dependency.network.outputs.private_subnet_ids
}
