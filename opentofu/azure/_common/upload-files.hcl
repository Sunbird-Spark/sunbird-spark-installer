# For local development
terraform {
  source = "../../modules//upload-files/"
}

locals {
  global_vars            = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  storage_account_name   = local.global_vars.global.azure_storage_account_name
  storage_container_public = local.global_vars.global.azure_storage_container_public
  storage_account_key    = local.global_vars.global.azure_storage_account_key
}

inputs = {
  storage_account_name               = local.storage_account_name
  storage_container_public           = local.storage_container_public
  storage_account_primary_access_key = local.storage_account_key
}