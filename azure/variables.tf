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
  description = "CPU cores for each agent container"
  type        = number
  default     = 4
}

variable "container_memory_gb" {
  description = "Memory in GB for each agent container"
  type        = number
  default     = 8
}

variable "job_timeout" {
  description = "Maximum run time per agent job in seconds"
  type        = number
  default     = 3600
}

variable "max_parallel_runs" {
  description = "Maximum number of parallel agent runs"
  type        = number
  default     = 10
}

variable "agent_environment" {
  type        = map(string)
  description = "Extra environment variables for the agent container, such as SCALR_AGENT_* options. Values are not secret"
  default     = {}
}

variable "scalr_url" {
  description = "Scalr URL the agent connects to, for a Scalr host other than <account>.scalr.io. Defaults to https://<account>.scalr.io"
  type        = string
  default     = null
}

variable "scalr_agent_cache_enabled" {
  type        = bool
  description = "Keep the Scalr agent cache (OpenTofu and Terraform binaries, providers, and modules) on a persistent volume, so later runs skip the downloads. All runs of the pool share the cache, so it suits a pool whose workspaces trust each other"
  default     = true
}
