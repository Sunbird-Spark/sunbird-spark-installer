output "resource_group_name" {
  value = local.resource_group_name
}

output "aks_subnet_id" {
  value = azurerm_subnet.aks_subnet.id
}

output "runner_subnet_id" {
  value = azurerm_subnet.runner_subnet.id
}

output "vnet_name" {
  value = azurerm_virtual_network.vnet.name
}