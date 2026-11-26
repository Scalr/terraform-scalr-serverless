output "storage_account_name" {
  description = "Storage account name for Azure Files cache"
  value       = azurerm_storage_account.cache.name
}

output "storage_account_key" {
  description = "Storage account primary access key"
  value       = azurerm_storage_account.cache.primary_access_key
  sensitive   = true
}

output "scalr_agent_cache_share_name" {
  description = "Azure Files share for the agent cache"
  value       = azurerm_storage_share.scalr_agent_cache.name
}
