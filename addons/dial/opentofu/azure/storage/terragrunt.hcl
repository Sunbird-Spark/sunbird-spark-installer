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

locals {
  # Read global values from main opentofu
  global_vars = yamldecode(file(find_in_parent_folders("global-values.yaml", "${get_repo_root()}/opentofu/azure/template/global-values.yaml")))
  cloud_vars  = yamldecode(file(find_in_parent_folders("global-cloud-values.yaml", "${get_repo_root()}/opentofu/azure/template/global-cloud-values.yaml")))
}

inputs = {
  environment          = local.cloud_vars.global.environment
  storage_account_name = local.cloud_vars.global.cloud_storage_access_key
  resource_group_name  = "${local.cloud_vars.global.building_block}-${local.cloud_vars.global.environment}"
  subscription_id      = local.global_vars.global.subscription_id
  unique_uuid          = local.cloud_vars.global.random_string
}
