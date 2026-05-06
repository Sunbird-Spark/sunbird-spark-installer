locals {
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  cloud_vars   = try(yamldecode(file("${dirname(find_in_parent_folders("global-values.yaml"))}/global-cloud-values.yaml")), {
    global = {
      public_container_name        = "dummy-public"
      private_container_name       = "dummy-private"
      velero_container_name        = "dummy-velero"
      dial_state_container_public  = "dummy-dial"
    }
  })

  skip_storage_module    = local.global_vars.global.skip_storage_module
  env                    = local.global_vars.global.env
  environment            = local.global_vars.global.environment
  building_block         = local.global_vars.global.building_block
  region                 = local.global_vars.global.cloud_storage_region
  project                = local.global_vars.global.cloud_storage_project
  cloud_storage_provider = local.global_vars.global.cloud_storage_provider
}

terraform {
  source = "../../modules//output-file/"
}

dependency "storage" {
  config_path  = "../storage"
  skip_outputs = local.skip_storage_module
  mock_outputs = {
    gcp_public_container_name             = "dummy-public"
    gcp_private_container_name            = "dummy-private"
    gcp_dial_state_container_public       = "dummy-dial"
    gcp_velero_storage_container_private  = "dummy-velero"
  }
  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "gke" {
  config_path = "../gke"
  mock_outputs = {
    storage_class             = "dummy"
    private_ingressgateway_ip = "0.0.0.0"
  }
}

dependency "keys" {
  config_path = "../keys"
  mock_outputs = {
    random_string = "dummy-string"
  }
}

dependency "workload-identity" {
  config_path = "../workload-identity"
  mock_outputs = {
    service_account_email     = "dummy-sa@dummy.iam.gserviceaccount.com"
    k8s_service_account_names = { sunbird = "sunbird-sa" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "validate"]
}

inputs = {
  env                              = local.env
  environment                      = local.environment
  building_block                   = local.building_block
  random_string                    = dependency.keys.outputs.random_string
  private_ingressgateway_ip        = dependency.gke.outputs.private_ingressgateway_ip
  storage_class                    = dependency.gke.outputs.storage_class
  cloud_storage_provider           = local.cloud_storage_provider
  cloud_storage_region             = local.region
  gcp_project_id                   = local.project
  service_account_email            = dependency.workload-identity.outputs.service_account_email
  k8s_service_account_name         = dependency.workload-identity.outputs.k8s_service_account_names["sunbird"]

  storage_container_public         = local.skip_storage_module ? local.cloud_vars.global.public_container_name        : dependency.storage.outputs.gcp_public_container_name
  storage_container_private        = local.skip_storage_module ? local.cloud_vars.global.private_container_name       : dependency.storage.outputs.gcp_private_container_name
  dial_state_container_public      = local.skip_storage_module ? local.cloud_vars.global.dial_state_container_public  : dependency.storage.outputs.gcp_dial_state_container_public
  velero_storage_container_private = local.skip_storage_module ? local.cloud_vars.global.velero_container_name        : dependency.storage.outputs.gcp_velero_storage_container_private
}
