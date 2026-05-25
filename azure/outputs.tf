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
  description = "Logic App HTTP trigger callback URL (webhook endpoint for Scalr)"
  value       = module.webhook.url
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

output "scalr_allowed_ips" {
  description = "Official Scalr.io IP addresses"
  value       = module.scalr_ips.allowed_ips
}

output "resource_group_name" {
  description = "Azure resource group name"
  value       = module.resource_group.name
}
