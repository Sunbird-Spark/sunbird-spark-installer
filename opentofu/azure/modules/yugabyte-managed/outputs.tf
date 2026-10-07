output "cluster_id" {
  value = ybm_cluster.this.cluster_id
}

output "private_host" {
  description = "The private hostname to connect to the cluster from inside the AKS VNet (resolves via the Private DNS Zone)."
  value       = ybm_private_service_endpoint.this.host
}

output "private_ip" {
  value = azurerm_private_endpoint.yugabyte.private_service_connection[0].private_ip_address
}
