output "runner_public_ip" {
  value       = azurerm_public_ip.runner_pip.ip_address
  description = "Public IP of runner VM. VPN clients connect here."
}

output "runner_private_ip" {
  value       = azurerm_network_interface.runner_nic.private_ip_address
  description = "Private IP of runner VM inside VNet."
}

output "runner_identity_principal_id" {
  value       = azurerm_user_assigned_identity.runner_identity.principal_id
  description = "Principal ID of VM managed identity."
}

output "runner_identity_id" {
  value       = azurerm_user_assigned_identity.runner_identity.id
  description = "Resource ID of VM managed identity."
}
