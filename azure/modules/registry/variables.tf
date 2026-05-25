variable "name" {
  description = "Name prefix for the container registry"
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

variable "source_image" {
  description = "Source Docker Hub image to import (e.g. docker.io/scalr/agent:latest)"
  type        = string
}
