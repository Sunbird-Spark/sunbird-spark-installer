output "client_id" {
  value       = azurerm_user_assigned_identity.workload_identity.client_id
  description = "Client ID of the user-assigned managed identity for workload identity."
}

output "k8s_service_account_names" {
  value       = { for k, v in kubernetes_service_account.workload_identity : k => v.metadata[0].name }
  description = "Map of service account names created per key (sunbird, velero, etc.)."
}

output "k8s_service_account_name" {
  value = kubernetes_service_account.workload_identity["sunbird"].metadata[0].name
  description = "Name of the Kubernetes service account for sunbird namespace. Error: 'sunbird' key must exist in k8s_service_accounts variable."
}
