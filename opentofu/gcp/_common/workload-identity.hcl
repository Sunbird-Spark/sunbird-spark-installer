locals {
  global_vars    = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars     = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {
    global = {
      public_container_name             = "dummy-public"
      private_container_name            = "dummy-private"
      velero_container_name             = "dummy-velero"
      dial_state_container_public       = "dummy-dial"
    }
  })

  skip_storage_module = local.global_vars.global.skip_storage_module
  environment         = local.global_vars.global.environment
  building_block      = local.global_vars.global.building_block
  project             = local.global_vars.global.cloud_storage_project
}

terraform {
  source = "../../modules//workload-identity/"
}

dependency "storage" {
  config_path  = "../storage"
  skip_outputs = local.skip_storage_module
  mock_outputs = {
    gcp_public_container_name             = "dummy-public"
    gcp_private_container_name            = "dummy-private"
    gcp_velero_storage_container_private  = "dummy-velero"
    gcp_dial_state_container_public       = "dummy-dial"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "gke" {
  config_path = "../gke"
  mock_outputs = {
    kubernetes_host                   = "dummy-host"
    kubernetes_cluster_ca_certificate = "dummy-ca"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "validate"]
}

inputs = {
  environment    = local.environment
  building_block = local.building_block
  project        = local.project

  kubernetes_host                   = dependency.gke.outputs.kubernetes_host
  kubernetes_cluster_ca_certificate = dependency.gke.outputs.kubernetes_cluster_ca_certificate

  container_names = local.skip_storage_module ? [
    local.cloud_vars.global.public_container_name,
    local.cloud_vars.global.private_container_name,
    local.cloud_vars.global.velero_container_name,
    local.cloud_vars.global.dial_state_container_public,
  ] : [
    dependency.storage.outputs.gcp_public_container_name,
    dependency.storage.outputs.gcp_private_container_name,
    dependency.storage.outputs.gcp_velero_storage_container_private,
    dependency.storage.outputs.gcp_dial_state_container_public,
  ]
}
