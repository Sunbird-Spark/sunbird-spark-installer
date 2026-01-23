output "client_id" {
  value       = azurerm_user_assigned_identity.content_service.client_id
  description = "Client ID of the managed identity"
}

output "content_service_principal_id" {
  value       = azurerm_user_assigned_identity.content_service.principal_id
  description = "Principal ID of the content service managed identity"
}

