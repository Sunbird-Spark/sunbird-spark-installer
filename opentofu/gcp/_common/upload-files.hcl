locals {
  global_vars = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars  = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {
    global = {
      public_container_name = "dummy-container-public"
    }
  })

  skip_storage_module = local.global_vars.global.skip_storage_module
  project             = local.global_vars.global.cloud_storage_project
}

terraform {
  source = "../../modules//upload-files/"
}

dependency "storage" {
  config_path  = "../storage"
  skip_outputs = local.skip_storage_module
  mock_outputs = {
    gcp_public_container_name = "dummy-container-public"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  storage_account_name     = "storage.googleapis.com"
  project_number           = local.project
  storage_container_public = local.skip_storage_module ? local.cloud_vars.global.public_container_name : dependency.storage.outputs.gcp_public_container_name
}
