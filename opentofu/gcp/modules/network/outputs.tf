locals {
  active_subnetwork = var.create_network ? google_compute_subnetwork.vpc_subnetwork_public[0] : data.google_compute_subnetwork.vpc_subnetwork_public[0]
}

output "network" {
  description = "A reference (self_link) to the VPC network"
  value       = local.active_network_self_link
}

output "network_name" {
  description = "Name of the VPC network"
  value       = local.active_network_name
}

# ---------------------------------------------------------------------------------------------------------------------
# Public Subnetwork Outputs
# ---------------------------------------------------------------------------------------------------------------------

output "public_subnetwork" {
  description = "A reference (self_link) to the public subnetwork"
  value       = local.active_subnetwork.self_link
}

output "public_subnetwork_name" {
  description = "Name of the public subnetwork"
  value       = local.active_subnetwork.name
}

output "public_subnetwork_cidr_block" {
  value = local.active_subnetwork.ip_cidr_range
}

output "public_subnetwork_gateway" {
  value = local.active_subnetwork.gateway_address
}

output "public_subnetwork_secondary_cidr_block" {
  value = local.active_subnetwork.secondary_ip_range[0].ip_cidr_range
}

output "public_subnetwork_secondary_range_name" {
  value = local.active_subnetwork.secondary_ip_range[0].range_name
}

output "public_services_secondary_cidr_block" {
  value = local.active_subnetwork.secondary_ip_range[1].ip_cidr_range
}

output "public_services_secondary_range_name" {
  value = local.active_subnetwork.secondary_ip_range[1].range_name
}
