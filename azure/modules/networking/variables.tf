variable "name" {
  description = "Name prefix for networking resources"
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

variable "address_space" {
  description = "VNet address space"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_prefix" {
  description = "Subnet address prefix (Container Apps needs at least /23)"
  type        = string
  default     = "10.0.0.0/23"
}
