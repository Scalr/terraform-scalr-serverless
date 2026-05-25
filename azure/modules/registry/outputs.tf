output "login_server" {
  description = "ACR login server hostname"
  value       = azurerm_container_registry.this.login_server
}

output "admin_username" {
  description = "ACR admin username"
  value       = azurerm_container_registry.this.admin_username
}

output "admin_password" {
  description = "ACR admin password"
  value       = azurerm_container_registry.this.admin_password
  sensitive   = true
}

output "image" {
  description = "Full ACR image reference (ready for ACI)"
  value       = "${azurerm_container_registry.this.login_server}/${local.image_ref}"
  depends_on  = [terraform_data.import_image]
}
