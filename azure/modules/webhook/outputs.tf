output "url" {
  description = "APIM webhook endpoint URL"
  value       = "${azurerm_api_management.this.gateway_url}/${azurerm_api_management_api.webhook.path}/"
}

output "api_key" {
  description = "API subscription key for webhook authentication (Ocp-Apim-Subscription-Key header)"
  value       = azurerm_api_management_subscription.webhook.primary_key
  sensitive   = true
}

output "environment_id" {
  description = "Container Apps environment ID"
  value       = azurerm_container_app_environment.this.id
}

output "environment_name" {
  description = "Container Apps environment name"
  value       = azurerm_container_app_environment.this.name
}

output "job_name" {
  description = "Container Apps Job name"
  value       = azurerm_container_app_job.scalr_agent.name
}

output "job_id" {
  description = "Container Apps Job ID"
  value       = azurerm_container_app_job.scalr_agent.id
}
