locals {
  # This section will be enabled after final code is pushed and tagged
  # source_base_url = "github.com/<org>/modules.git//app"
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  env = local.global_vars.global.env
  environment  = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
  cloud_storage_provider = local.global_vars.global.cloud_storage_provider
  cloud_storage_region = local.global_vars.global.cloud_storage_region
  # random_string  = local.environment_vars.locals.random_string
}

# For local development
terraform {
  source = "../../modules//output-file/"
}

dependency "storage" {
    config_path = "../storage"
    mock_outputs = {
      public_bucket_name = "dummy-bucket-public"
      private_bucket_name = "dummy-bucket-private"
      dial_bucket_name = "dummy-bucket-dial"
      velero_bucket_name = "dummy-bucket-velero"
    }
}

dependency "eks" {
    config_path = "../eks"
    mock_outputs = {
      cluster_endpoint = "dummy-endpoint"
    }
}

dependency "keys" {
    config_path = "../keys"
    mock_outputs = {
      random_string = "dummy-string"
      encryption_string = "dummy-encryption-string"
    }
}

inputs = {
  env                                = local.env
  environment                        = local.environment
  building_block                     = local.building_block
  private_ingressgateway_ip          = ""  # Will be set after ingress controller is deployed
  storage_container_public           = dependency.storage.outputs.public_bucket_name
  storage_container_private          = dependency.storage.outputs.private_bucket_name
  dial_state_container_public        = dependency.storage.outputs.dial_bucket_name
  velero_storage_container_private   = dependency.storage.outputs.velero_bucket_name
  encryption_string                  = dependency.keys.outputs.encryption_string
  random_string                      = dependency.keys.outputs.random_string
  cloud_storage_provider             = local.cloud_storage_provider
  cloud_storage_region               = local.cloud_storage_region
  aws_storage_account_mail           = ""  # IAM role ARN for storage access
  aws_storage_bucket_key             = ""  # Not needed with IAM roles
  aws_account_id                     = get_aws_account_id()
  service_account_role_arn           = ""  # To be configured for service accounts
}