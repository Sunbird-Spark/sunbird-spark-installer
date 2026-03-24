output "client_id" {
  value       = azurerm_user_assigned_identity.workload_identity.client_id
  description = "Client ID of the user-assigned managed identity for workload identity."
}

output "k8s_service_account_name" {
  value       = kubernetes_service_account.workload_identity.metadata[0].name
  description = "Name of the Kubernetes service account created by infrastructure."
}
