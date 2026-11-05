output "random_string" {
  value = random_password.generated_string.result
  sensitive = true
}

output "key_vault_id" {
  value = azurerm_key_vault.vault.id
}
