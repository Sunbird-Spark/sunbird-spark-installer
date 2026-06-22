output "resource_group_name" {
  value = local.resource_group_name
}

output "aks_subnet_id" {
  value = var.skip_network_module ? data.azurerm_subnet.aks_subnet[0].id : azurerm_subnet.aks_subnet[0].id
}

output "runner_subnet_id" {
  value = var.skip_network_module ? data.azurerm_subnet.runner_subnet[0].id : azurerm_subnet.runner_subnet[0].id
}

output "vnet_name" {
  value = var.skip_network_module ? data.azurerm_virtual_network.vnet[0].name : azurerm_virtual_network.vnet[0].name
}
