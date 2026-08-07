terraform {
  source = "."
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
  terraform {
    backend "azurerm" {
      resource_group_name  = "${get_env("AZURE_OPENTOFU_BACKEND_RG")}"
      storage_account_name = "${get_env("AZURE_OPENTOFU_BACKEND_STORAGE_ACCOUNT")}"
      container_name       = "${get_env("AZURE_OPENTOFU_BACKEND_CONTAINER")}"
      key                  = "addons/dial/storage/tofu.tfstate"
    }
  }
EOF
}

skip = local.skip_storage_module

locals {
  env_name            = get_env("ENV_NAME")
  repo_root           = get_repo_root()
  global_vars         = yamldecode(file("${local.repo_root}/opentofu/azure/${local.env_name}/global-values.yaml"))
  cloud_vars          = try(yamldecode(file("${local.repo_root}/opentofu/azure/${local.env_name}/global-cloud-values.yaml")), { global: { cloud_storage_access_key: "" } })
  skip_storage_module = local.global_vars.global.skip_storage_module
}

inputs = {
  environment                    = local.global_vars.global.environment
  storage_account_name           = local.cloud_vars.global.cloud_storage_access_key
  resource_group_name            = "${local.global_vars.global.building_block}-${local.global_vars.global.environment}"
  subscription_id                = local.global_vars.global.subscription_id
  building_block                 = local.global_vars.global.building_block
  global_cloud_values_file       = "${get_repo_root()}/addons/global-cloud-values.yaml"
  workload_identity_principal_id = try(local.cloud_vars.global.managed_identity_principal_id, "")
}

