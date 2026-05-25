variable "azure_location" {
  description = "Azure region for deployment"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Azure resource group name"
  type        = string
  default     = "scalr-serverless-rg"
}

variable "name_prefix" {
  description = "Prefix for Azure resource names"
  type        = string
  default     = "scalr-agent"
}

variable "allow_all_ingress" {
  description = "Whether to allow all ingress traffic (overrides Scalr IP whitelist)"
  type        = bool
  default     = false
}

variable "agent_pool_name" {
  description = "Scalr serverless agent pool name"
  type        = string
  default     = "azure-serverless"
}

variable "container_image" {
  description = "Container image for on-demand Scalr agent runs"
  type        = string
  default     = "scalr/agent:latest"
}

variable "container_cpu" {
  description = "CPU cores for each agent container instance"
  type        = number
  default     = 2
}

variable "container_memory_gb" {
  description = "Memory in GB for each agent container instance"
  type        = number
  default     = 4
}

variable "scalr_webhook_url" {
  description = "Scalr agent pool webhook URL. Leave empty on first apply, then set to the webhook_url output and re-apply to register the pool."
  type        = string
  default     = ""
  sensitive   = true
}
