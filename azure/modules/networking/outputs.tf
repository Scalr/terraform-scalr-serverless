output "vnet_id" {
  description = "Virtual network ID"
  value       = azurerm_virtual_network.main.id
}

output "subnet_id" {
  description = "Subnet ID for Container Apps environment"
  value       = azurerm_subnet.container_apps.id
}
