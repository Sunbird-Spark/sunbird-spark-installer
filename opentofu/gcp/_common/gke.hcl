locals {
  # This section will be enabled after final code is pushed and tagged
  # source_base_url = "github.com/<org>/modules.git//app"
  global_vars  = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment  = local.global_vars.global.environment
  building_block = local.global_vars.global.building_block
  project = local.global_vars.global.cloud_storage_project
  zone = local.global_vars.global.zone
  location= local.global_vars.global.cloud_storage_region
  create_network= local.global_vars.global.create_network
  gke_node_pool_instance_type= local.global_vars.global.gke_node_pool_instance_type
  gke_node_default_disk_size_gb= local.global_vars.global.gke_node_default_disk_size_gb
  region = local.global_vars.global.cloud_storage_region
  env = local.global_vars.global.env
  # random_string  = local.environment_vars.locals.random_string

  # Private-cluster settings — equivalent of Azure's private_cluster_enabled.
  # Only safe to default true once the runner VM lives in this same VPC (see
  # gcp-setup-installer-vm.sh) — the private control-plane endpoint is only
  # reachable from within the VPC (or an authorized network).
  enable_private_nodes    = local.global_vars.global.enable_private_gke_nodes
  disable_public_endpoint = local.global_vars.global.disable_public_gke_endpoint
}

# For local development
terraform {
  source = "../../modules//gke/"
}

dependency "network" {
    config_path = "../network"
    mock_outputs = {
    network = "sunbird-vpc"
    public_subnetwork = "dummy"
    subnetwork = "dummy"
    public_services_secondary_range_name = "dummy"
    public_subnetwork_cidr_block = "10.0.0.0/20"
    }
}

inputs = {
  environment                        = local.environment
  building_block                     = local.building_block
  network                            = dependency.network.outputs.network
  subnetwork                         = dependency.network.outputs.public_subnetwork
  cluster_secondary_range_name      = dependency.network.outputs.public_services_secondary_range_name
  project                            = local.project
  zone                               = local.zone
  region                             = local.region
  location                           = local.location
  create_network                     = local.create_network
  gke_node_pool_instance_type        = local.gke_node_pool_instance_type
  gke_node_default_disk_size_gb      = local.gke_node_default_disk_size_gb
  env                              = local.env

  enable_private_nodes    = local.enable_private_nodes
  disable_public_endpoint = local.disable_public_endpoint
  # The runner VM (and anything else in this VPC's public subnetwork) needs
  # to reach the private control-plane endpoint — authorize the subnet it
  # lives in explicitly rather than relying on same-VPC access alone, since
  # GKE's own enforcement of that has changed across releases.
  master_authorized_networks_config = [{
    cidr_blocks = [{
      cidr_block   = dependency.network.outputs.public_subnetwork_cidr_block
      display_name = "${local.building_block}-${local.environment}-subnetwork-public"
    }]
  }]
}