output "url" {
  description = "Logic App HTTP trigger callback URL (webhook endpoint for Scalr)"
  value       = azurerm_logic_app_trigger_http_request.this.callback_url
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
