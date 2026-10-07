terraform {
  source = "../../modules//upload-files/"
}

locals {
  global_vars         = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars          = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {global: {public_container_name: "", cloud_storage_access_key: ""}})
  skip_storage_module = local.global_vars.global.skip_storage_module
  region              = local.global_vars.global.cloud_storage_region
  sunbird_player_editor_ref = try(local.global_vars.global.sunbird_player_editor_ref, "master")
  knowledge_platform_ref    = try(local.global_vars.global.knowledge_platform_ref, "master")
  public_artifacts_path     = "${get_repo_root()}/public-artifacts"
}

dependency "storage" {
  config_path  = "../storage"
  skip_outputs = local.skip_storage_module
  mock_outputs = {
    s3_bucket_public = "dummy-bucket-public"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  s3_bucket_public          = local.skip_storage_module ? local.cloud_vars.global.public_container_name : dependency.storage.outputs.s3_bucket_public
  aws_region                = local.region
  sunbird_player_editor_ref = local.sunbird_player_editor_ref
  knowledge_platform_ref    = local.knowledge_platform_ref
  public_artifacts_path     = local.public_artifacts_path
}
