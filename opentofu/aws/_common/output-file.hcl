locals {
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  _cloud_defaults = {public_container_name: "", private_container_name: "", velero_storage_container_private: "", sunbird_encryption_key: ""}
  _cloud_raw      = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {})
  cloud_vars      = {global: merge(local._cloud_defaults, try(local._cloud_raw.global, {}))}
  env                    = local.global_vars.global.env
  environment            = local.global_vars.global.environment
  building_block         = local.global_vars.global.building_block
  region                 = local.global_vars.global.cloud_storage_region
  cloud_storage_provider = local.global_vars.global.cloud_storage_provider
  s3_bucket_public       = local.cloud_vars.global.public_container_name
  s3_bucket_private      = local.cloud_vars.global.private_container_name
  s3_bucket_velero       = local.cloud_vars.global.velero_storage_container_private
  sunbird_encryption_key = local.cloud_vars.global.sunbird_encryption_key
}

# For local development
terraform {
  source = "../../modules//output-file/"
}

dependency "eks" {
  config_path = "../eks"
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    s3_bucket_public  = "dummy-public"
    s3_bucket_private = "dummy-private"
    s3_bucket_velero  = "dummy-velero"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply", "validate", "output"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "workload_identity" {
  config_path = "../workload-identity"
  mock_outputs = {
    iam_role_arn = "arn:aws:iam::000000000000:role/dummy-workload-identity"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply", "validate", "output"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "keys" {
  config_path = "../keys"
  mock_outputs = {
    random_string = "dummy-string"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply", "validate", "output"]
}


inputs = {
  env                       = local.env
  environment               = local.environment
  building_block            = local.building_block
  aws_region                = local.region
  cloud_storage_provider    = local.cloud_storage_provider
  private_ingressgateway_ip = dependency.eks.outputs.private_ingressgateway_ip
  s3_bucket_public          = coalesce(local.s3_bucket_public, dependency.storage.outputs.s3_bucket_public)
  s3_bucket_private         = coalesce(local.s3_bucket_private, dependency.storage.outputs.s3_bucket_private)
  s3_bucket_velero          = coalesce(local.s3_bucket_velero, dependency.storage.outputs.s3_bucket_velero)
  random_string             = dependency.keys.outputs.random_string
  aws_iam_role_arn          = dependency.workload_identity.outputs.iam_role_arn
  k8s_service_account_name  = "aws-irsa-sa"
  sunbird_encryption_key    = local.sunbird_encryption_key
}
