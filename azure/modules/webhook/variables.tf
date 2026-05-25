variable "name" {
  description = "Name prefix for webhook resources"
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

variable "resource_group_id" {
  description = "Resource group ID (for role assignment scope)"
  type        = string
}

variable "allow_all_ingress" {
  description = "Reserved for future IP restrictions (Logic App Consumption has no App Service Plan)"
  type        = bool
  default     = false
}

variable "allowed_ips" {
  description = "Reserved for future IP restrictions on the webhook endpoint"
  type        = list(string)
  default     = []
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "subnet_id" {
  description = "Optional subnet ID for Azure Container Instances"
  type        = string
  default     = ""
}

variable "container_image" {
  description = "Container image for Scalr agent runs"
  type        = string
}

variable "container_cpu" {
  description = "Container CPU cores for each agent run"
  type        = number
  default     = 2
}

variable "container_memory_gb" {
  description = "Container memory in GB for each agent run"
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
  description = "Container registry login server (e.g. myacr.azurecr.io). Leave empty to pull from Docker Hub."
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
