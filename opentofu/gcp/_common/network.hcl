locals {
  # Load YAML file instead of environment.hcl
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment  = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
  project = local.global_vars.global.cloud_storage_project
  region = local.global_vars.global.cloud_storage_region

  # create_network = true:  this module creates the VPC/subnetwork
  # create_network = false: reuse an existing VPC/subnetwork (names from
  #                          network/subnetwork below — e.g. pre-created by
  #                          gcp-setup-installer-vm.sh) via data source
  create_network = try(local.global_vars.global.create_network, true)
  network        = try(local.global_vars.global.network, "")
  subnetwork     = try(local.global_vars.global.subnetwork, "")
}

# For local development
terraform {
  source = "../../modules//network/"
}

inputs = {
  environment         = local.environment
  building_block      = local.building_block
  project             = local.project
  region              = local.region
  create_network      = local.create_network
  network             = local.network
  subnetwork          = local.subnetwork
}