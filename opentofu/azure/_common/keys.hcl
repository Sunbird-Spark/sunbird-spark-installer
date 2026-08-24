locals {
  # This section will be enabled after final code is pushed and tagged
  # source_base_url = "github.com/<org>/modules.git//app"
  global_vars         = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars          = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {global: {cloud_storage_access_key: "", public_container_name: "", private_container_name: ""}})
  skip_storage_module = local.global_vars.global.skip_storage_module
  environment         = local.global_vars.global.environment
  building_block      = local.global_vars.global.building_block
  subscription_id     = local.global_vars.global.subscription_id
  location             = local.global_vars.global.cloud_storage_region
  # random_string  = local.environment_vars.locals.random_string
}

# For local development
terraform {
  source = "../../modules//keys/"
}

dependency "network" {
    config_path = "../network"
    mock_outputs = {
      resource_group_name = "dummy-rg"
      aks_subnet_id        = "dummy-aks-subnet-id"
      runner_subnet_id     = "dummy-runner-subnet-id"
    }
}

dependency "storage" {
    config_path  = "../storage"
    skip_outputs = local.skip_storage_module
    mock_outputs = {
      azurerm_storage_account_name         = "dummy-account"
      azurerm_private_storage_account_name = "dummy-account-priv"
      azurerm_storage_container_public     = "dummy-container-public"
      azurerm_storage_container_private    = "dummy-container-private"
    }
    mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "random_passwords" {
  config_path = "../random_passwords"
  mock_outputs = {
    grafana_admin_password  = "dummy"
    superset_admin_password = "dummy"
    keycloak_password       = "dummy"
  }
}

inputs = {
  environment               = local.environment
  building_block            = local.building_block
  subscription_id           = local.subscription_id
  location                  = local.location
  resource_group_name       = dependency.network.outputs.resource_group_name
  aks_subnet_id             = dependency.network.outputs.aks_subnet_id
  runner_subnet_id          = dependency.network.outputs.runner_subnet_id
  # The JWT/RSA blobs this module uploads go to the private container, which
  # now lives on the private (firewalled) account, not the public one.
  storage_account_name      = local.skip_storage_module ? try(local.cloud_vars.global.private_cloud_storage_access_key, local.cloud_vars.global.cloud_storage_access_key) : dependency.storage.outputs.azurerm_private_storage_account_name
  storage_container_public  = local.skip_storage_module ? local.cloud_vars.global.public_container_name : dependency.storage.outputs.azurerm_storage_container_public
  storage_container_private = local.skip_storage_module ? local.cloud_vars.global.private_container_name : dependency.storage.outputs.azurerm_storage_container_private
  grafana_admin_password    = dependency.random_passwords.outputs.grafana_admin_password
  superset_admin_password   = dependency.random_passwords.outputs.superset_admin_password
  keycloak_password         = dependency.random_passwords.outputs.keycloak_password
  # random_string           = local.random_string
}
