output "url" {
  description = "Logic App HTTP trigger callback URL (includes SAS authentication)"
  value       = azurerm_logic_app_trigger_http_request.this.callback_url
  sensitive   = true
}

output "workflow_name" {
  description = "Logic App workflow name"
  value       = azurerm_logic_app_workflow.this.name
}

output "workflow_id" {
  description = "Logic App workflow ID"
  value       = azurerm_logic_app_workflow.this.id
}
