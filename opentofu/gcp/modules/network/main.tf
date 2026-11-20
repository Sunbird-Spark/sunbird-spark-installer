# ---------------------------------------------------------------------------------------------------------------------
# Create the Network & corresponding Router to attach other resources to
# Networks that preserve the default route are automatically enabled for Private Google Access to GCP services
# provided subnetworks each opt-in; in general, Private Google Access should be the default.
# ---------------------------------------------------------------------------------------------------------------------

locals {
    # No common_tags/labels here -- none of google_compute_network,
    # google_compute_subnetwork, google_compute_router, or
    # google_compute_firewall support a labels attribute (verified against
    # the real provider schema), unlike GCP's storage/gke modules.
    environment_name = "${var.building_block}-${var.environment}"

    # create_network = true:  OpenTofu creates the VPC/subnetwork via resource blocks below
    # create_network = false: reuse an existing VPC/subnetwork via data sources (names from
    #                          var.network/var.subnetwork — e.g. pre-created by
    #                          gcp-setup-installer-vm.sh so the runner VM and GKE share a VPC)
    network_name    = var.network != "" ? var.network : "${local.environment_name}-network"
    subnetwork_name = var.subnetwork != "" ? var.subnetwork : "${local.environment_name}-subnetwork-public"

    active_network_self_link = var.create_network ? google_compute_network.vpc[0].self_link : data.google_compute_network.vpc[0].self_link
    active_network_name      = var.create_network ? google_compute_network.vpc[0].name : data.google_compute_network.vpc[0].name
}

data "google_compute_network" "vpc" {
  count   = var.create_network ? 0 : 1
  name    = local.network_name
  project = var.project
}

data "google_compute_subnetwork" "vpc_subnetwork_public" {
  count   = var.create_network ? 0 : 1
  name    = local.subnetwork_name
  region  = var.region
  project = var.project
}

resource "google_compute_network" "vpc" {
  count   = var.create_network ? 1 : 0
  name    = local.network_name
  project = var.project

  # Always define custom subnetworks- one subnetwork per region isn't useful for an opinionated setup
  auto_create_subnetworks = false

  # A global routing mode can have an unexpected impact on load balancers; always use a regional mode
  routing_mode = "REGIONAL"
}

resource "google_compute_router" "vpc_router" {
  name = "${local.environment_name}-router"

  project = var.project
  region  = var.region
  network = local.active_network_self_link
}

# Referenced by the comment below but never actually implemented until now —
# without this, nodes with no external IP (enable_private_nodes = true) have
# NO internet egress at all and can't pull any container image.
resource "google_compute_router_nat" "vpc_nat" {
  name    = "${local.environment_name}-nat"
  project = var.project
  region  = var.region
  router  = google_compute_router.vpc_router.name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Public Subnetwork Config
# Public internet access for instances with addresses is automatically configured by the default gateway for 0.0.0.0/0
# External access is configured with Cloud NAT, which subsumes egress traffic for instances without external addresses
# ---------------------------------------------------------------------------------------------------------------------

resource "google_compute_subnetwork" "vpc_subnetwork_public" {
  count = var.create_network ? 1 : 0

  name = local.subnetwork_name

  project = var.project
  region  = var.region
  network = google_compute_network.vpc[0].self_link

  private_ip_google_access = true
  ip_cidr_range            = cidrsubnet(var.vpc_cidr_block, var.secondary_cidr_subnetwork_width_delta, 0)

  secondary_ip_range {
    range_name = var.public_subnetwork_secondary_range_name
    ip_cidr_range = cidrsubnet(
      var.vpc_secondary_cidr_block,
      var.secondary_cidr_subnetwork_width_delta,
      0
    )
  }

  secondary_ip_range {
    range_name = var.public_services_secondary_range_name
    ip_cidr_range = var.public_services_secondary_cidr_block != null ? var.public_services_secondary_cidr_block : cidrsubnet(
      var.vpc_secondary_cidr_block,
      var.secondary_cidr_subnetwork_width_delta,
      1 * (2 + var.secondary_cidr_subnetwork_spacing)
    )
  }

  dynamic "log_config" {
    for_each = var.log_config == null ? [] : tolist([var.log_config])

    content {
      aggregation_interval = var.log_config.aggregation_interval
      flow_sampling        = var.log_config.flow_sampling
      metadata             = var.log_config.metadata
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Attach Firewall Rules to allow inbound traffic to tagged instances
# ---------------------------------------------------------------------------------------------------------------------

# IAP (Identity-Aware Proxy) tunneling range -- this is what makes
# `gcloud compute ssh --tunnel-through-iap` work against the runner VM when
# vpn_enabled=false. IAP itself is the real access-control layer (requires
# roles/iap.tunnelResourceAccessor on the caller); this rule only opens the
# path, it doesn't grant access on its own. Mirrors Azure's Bastion path
# (modules/network/main.tf's azurerm_bastion_host), which needs no equivalent
# firewall rule since Azure's default NSG already allows Bastion->VNet.
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "${local.environment_name}-allow-iap-ssh"
  network = local.active_network_name
  project = var.project

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  direction     = "INGRESS"
}

# Note: Pritunl VPN firewall rules (UDP 1194, TCP 443) for the runner VM are
# deliberately NOT managed here — gcp-setup-installer-vm.sh creates them
# directly, before this module ever runs (the runner VM has to be reachable
# before `create_tf_resources` exists to run this module at all). Mirrors
# Azure's pattern: setup-installer-vm.sh manages the VM's own NSG rules
# directly, untouched by the OpenTofu network module.
