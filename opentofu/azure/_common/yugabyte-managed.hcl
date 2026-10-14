locals {
  global_vars     = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment     = local.global_vars.global.environment
  subscription_id = local.global_vars.global.subscription_id
}

terraform {
  source = "../../modules//yugabyte-managed/"
}

dependency "network" {
  config_path = "../network"
  mock_outputs = {
    resource_group_name = "dummy-rg"
    vnet_name            = "dummy-vnet"
    aks_subnet_id         = "dummy-subnet-id"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  environment         = local.environment
  subscription_id     = local.subscription_id
  resource_group_name = dependency.network.outputs.resource_group_name
  aks_vnet_name       = dependency.network.outputs.vnet_name
  aks_subnet_id       = dependency.network.outputs.aks_subnet_id
  ybm_auth_token      = local.global_vars.global.yugabyte_managed_auth_token
  db_username         = local.global_vars.global.yugabyte_managed_db_username
  db_password         = local.global_vars.global.yugabyte_managed_db_password
}
