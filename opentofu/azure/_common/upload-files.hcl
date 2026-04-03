terraform {
  source = "../../modules//upload-files/"
}

locals {
  global_vars            = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars             = yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml"))
  storage_account_name   = local.cloud_vars.global.cloud_storage_access_key
  storage_container_public = local.cloud_vars.global.public_container_name
  storage_account_key    = local.cloud_vars.global.cloud_storage_secret_key
}

dependency "workload_identity" {
  config_path = "../workload-identity"
  mock_outputs = {
    deployer_role_ready = "mock"
  }
}

inputs = {
  storage_account_name               = local.storage_account_name
  storage_container_public           = local.storage_container_public
  storage_account_primary_access_key = local.storage_account_key
}
