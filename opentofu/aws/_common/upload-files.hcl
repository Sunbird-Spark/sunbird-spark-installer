# For local development
terraform {
  source = "../../modules//upload-files/"
}

locals {
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  region = local.global_vars.global.cloud_storage_region
}

dependency "storage" {
    config_path = "../storage"
    mock_outputs = {
      public_bucket_name = "dummy-bucket"
    }
}

inputs = {
  region                 = local.region
  storage_account_name   = dependency.storage.outputs.public_bucket_name
  storage_container_public = dependency.storage.outputs.public_bucket_name
  aws_access_key_id = get_env("AWS_ACCESS_KEY_ID", "")
  aws_secret_access_key = get_env("AWS_SECRET_ACCESS_KEY", "")
  sunbird_public_artifacts_bucket = get_env("SUNBIRD_PUBLIC_ARTIFACTS_BUCKET", "sunbird-public-dev")
  sunbird_public_artifacts_access_key_id = get_env("SUNBIRD_PUBLIC_ARTIFACTS_ACCESS_KEY_ID", "")
  sunbird_public_artifacts_secret_access_key = get_env("SUNBIRD_PUBLIC_ARTIFACTS_SECRET_ACCESS_KEY", "")
  sunbird_public_artifacts_container = get_env("SUNBIRD_PUBLIC_ARTIFACTS_CONTAINER", "release700")
  # Use defaults from variables.tf for Azure credentials
  # sunbird_public_artifacts_account default: "downloadableartifacts"
  # sunbird_public_artifacts_account_sas_url has the SAS token with read permissions
}