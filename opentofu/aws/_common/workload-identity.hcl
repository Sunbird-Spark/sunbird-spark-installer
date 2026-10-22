locals {
  global_vars         = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars          = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {global: {cloud_storage_access_key: "dummy", public_container_name: "dummy", private_container_name: "dummy", velero_storage_container_private: "dummy"}})
  skip_storage_module = local.global_vars.global.skip_storage_module
  environment         = local.global_vars.global.environment
  building_block      = local.global_vars.global.building_block
  region              = local.global_vars.global.cloud_storage_region
}

terraform {
  source = "../../modules//workload-identity/"
}

dependency "eks" {
  config_path = "../eks"
  mock_outputs = {
    oidc_issuer_url        = "https://oidc.eks.ap-south-1.amazonaws.com/id/DUMMY"
    cluster_name           = "dummy-cluster"
    kubernetes_host        = "https://dummy.gr7.ap-south-1.eks.amazonaws.com"
    cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t..."
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "apply", "destroy", "init"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "storage" {
  config_path  = "../storage"
  skip_outputs = local.skip_storage_module
  mock_outputs = {
    s3_bucket_public_arn  = "arn:aws:s3:::dummy-public"
    s3_bucket_private_arn = "arn:aws:s3:::dummy-private"
    s3_bucket_velero_arn  = "arn:aws:s3:::dummy-velero"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  environment                       = local.environment
  building_block                    = local.building_block
  region                            = local.region
  cluster_name                      = dependency.eks.outputs.cluster_name
  oidc_issuer_url                   = dependency.eks.outputs.oidc_issuer_url
  kubernetes_host                   = dependency.eks.outputs.kubernetes_host
  kubernetes_cluster_ca_certificate = dependency.eks.outputs.cluster_ca_certificate
  bucket_arns = local.skip_storage_module ? [
    "arn:aws:s3:::${local.cloud_vars.global.public_container_name}",
    "arn:aws:s3:::${local.cloud_vars.global.private_container_name}",
    "arn:aws:s3:::${local.cloud_vars.global.velero_storage_container_private}",
  ] : [
    dependency.storage.outputs.s3_bucket_public_arn,
    dependency.storage.outputs.s3_bucket_private_arn,
    dependency.storage.outputs.s3_bucket_velero_arn,
  ]
}
