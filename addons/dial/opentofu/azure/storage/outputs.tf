output "dial_state_container_name" {
  value       = azurerm_storage_container.dial_state_container_public.name
  description = "DIAL state container name"
}

output "storage_account_name" {
  value       = data.azurerm_storage_account.existing.name
  description = "Storage account name"
}
