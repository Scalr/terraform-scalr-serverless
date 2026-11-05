output "agent_pool_id" {
  description = "The ID of the created Scalr agent pool"
  value       = module.agent_pool.agent_pool_id
}

output "agent_token" {
  description = "The token for the Scalr agent"
  value       = module.agent_pool.agent_token
  sensitive   = true
}

output "webhook_url" {
  description = "APIM webhook endpoint URL"
  value       = module.webhook.url
}

output "api_key" {
  description = "APIM subscription key for webhook authentication"
  value       = module.webhook.api_key
  sensitive   = true
}

output "container_app_environment" {
  description = "Container Apps environment name"
  value       = module.webhook.environment_name
}

output "container_app_job" {
  description = "Container Apps Job name"
  value       = module.webhook.job_name
}

output "resource_group_name" {
  description = "Azure resource group name"
  value       = module.resource_group.name
}
