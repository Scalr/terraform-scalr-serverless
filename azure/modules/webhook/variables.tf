variable "name" {
  description = "Name prefix for Container Apps resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "subnet_id" {
  description = "Optional subnet ID for the Container Apps environment"
  type        = string
  default     = ""
}

variable "container_image" {
  description = "Container image for Scalr agent runs"
  type        = string
}

variable "container_cpu" {
  description = "CPU cores for each agent container"
  type        = number
  default     = 2
}

variable "container_memory_gb" {
  description = "Memory in GB for each agent container"
  type        = number
  default     = 4
}

variable "scalr_url" {
  description = "Scalr account URL"
  type        = string
}

variable "scalr_agent_token" {
  description = "Scalr agent pool token"
  type        = string
  sensitive   = true
}

variable "registry_server" {
  description = "Container registry login server (e.g. myacr.azurecr.io)"
  type        = string
  default     = ""
}

variable "registry_username" {
  description = "Container registry username"
  type        = string
  default     = ""
}

variable "registry_password" {
  description = "Container registry password"
  type        = string
  default     = ""
  sensitive   = true
}

variable "storage_account_name" {
  description = "Azure Files storage account name for cache (optional)"
  type        = string
  default     = ""
}

variable "storage_account_key" {
  description = "Azure Files storage account key for cache (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "terraform_cache_share_name" {
  description = "Azure Files share for Terraform module cache"
  type        = string
  default     = ""
}

variable "providers_cache_share_name" {
  description = "Azure Files share for Terraform provider cache"
  type        = string
  default     = ""
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
