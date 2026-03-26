output "client_id" {
  value       = azurerm_user_assigned_identity.workload_identity.client_id
  description = "Client ID of the user-assigned managed identity for workload identity."
}

output "tenant_id" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Azure tenant ID."
}

output "k8s_service_account_names" {
  value       = { for k, v in kubernetes_service_account.workload_identity : k => v.metadata[0].name }
  description = "Map of service account names created per key (sunbird, velero, etc.)."
}

output "managed_identity_principal_id" {
  value       = azurerm_user_assigned_identity.workload_identity.principal_id
  description = "Principal ID of the user-assigned managed identity."
}
