locals {
  # Load YAML file instead of environment.hcl
  global_vars             = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment             = local.global_vars.global.environment
  building_block          = local.global_vars.global.building_block
  subscription_id         = local.global_vars.global.subscription_id
  location                = local.global_vars.global.cloud_storage_region
  resource_group_name     = get_env("AZURE_OPENTOFU_BACKEND_RG")
  skip_network_module = try(local.global_vars.global.skip_network_module, false)
  vnet_name              = try(local.global_vars.global.vnet_name, "")
  aks_subnet_name        = try(local.global_vars.global.aks_subnet_name, "")
  runner_subnet_name     = try(local.global_vars.global.runner_subnet_name, "")
  vpn_enabled            = try(local.global_vars.global.vpn_enabled, true)
}

# For local development
terraform {
  source = "../../modules//network/"
}

inputs = {
  environment             = local.environment
  building_block          = local.building_block
  subscription_id         = local.subscription_id
  location                = local.location
  resource_group_name     = get_env("AZURE_OPENTOFU_BACKEND_RG")
  skip_network_module = local.skip_network_module
  vnet_name              = local.vnet_name
  aks_subnet_name        = local.aks_subnet_name
  runner_subnet_name     = local.runner_subnet_name
  vpn_enabled            = local.vpn_enabled
}
