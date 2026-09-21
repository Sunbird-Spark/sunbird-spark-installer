locals {
  global_vars = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars  = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {
    global = {
      public_container_name = "dummy-container-public"
    }
  })

  skip_storage_module       = local.global_vars.global.skip_storage_module
  sunbird_player_editor_ref = try(local.global_vars.global.sunbird_player_editor_ref, "master")
  knowledge_platform_ref    = try(local.global_vars.global.knowledge_platform_ref, "master")
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
  storage_account_name      = "storage.googleapis.com"
  storage_container_public  = local.skip_storage_module ? local.cloud_vars.global.public_container_name : dependency.storage.outputs.gcp_public_container_name
  public_artifacts_path     = "${get_repo_root()}/public-artifacts"
  sunbird_player_editor_ref = local.sunbird_player_editor_ref
  knowledge_platform_ref    = local.knowledge_platform_ref
}
