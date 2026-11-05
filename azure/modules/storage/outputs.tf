output "storage_account_name" {
  description = "Storage account name for Azure Files cache"
  value       = azurerm_storage_account.cache.name
}

output "storage_account_key" {
  description = "Storage account primary access key"
  value       = azurerm_storage_account.cache.primary_access_key
  sensitive   = true
}

output "terraform_cache_share_name" {
  description = "Azure Files share for Terraform module cache"
  value       = azurerm_storage_share.terraform_cache.name
}

output "providers_cache_share_name" {
  description = "Azure Files share for Terraform provider cache"
  value       = azurerm_storage_share.providers_cache.name
}
