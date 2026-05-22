output "resource_group_name" {
  value = local.resource_group_name
}

output "aks_subnet_id" {
  value = azurerm_subnet.aks_subnet.id
}