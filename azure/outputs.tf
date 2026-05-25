output "agent_pool_id" {
  description = "The ID of the created Scalr agent pool"
  value       = module.agent_pool.agent_pool_id
}

output "agent_token" {
  description = "The token for the Scalr agent (used by container instances)"
  value       = module.agent_pool.agent_token
  sensitive   = true
}

output "webhook_url" {
  description = "Logic App HTTP trigger callback URL (set scalr_webhook_url to this value and re-apply to link the Scalr agent pool)"
  value       = module.webhook.url
  sensitive   = true
}

output "logic_app_workflow_name" {
  description = "Azure Logic App workflow name"
  value       = module.webhook.workflow_name
}

output "scalr_allowed_ips" {
  description = "Official Scalr.io IP addresses (for optional front-door / APIM IP filtering)"
  value       = module.scalr_ips.allowed_ips
}

output "resource_group_name" {
  description = "Azure resource group name"
  value       = module.resource_group.name
}
