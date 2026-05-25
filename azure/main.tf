terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    scalr = {
      source = "scalr/scalr"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  use_cli = true
}

data "azurerm_client_config" "current" {}

module "scalr_ips" {
  source = "../modules/common/scalr-ips"
}

module "resource_group" {
  source = "./modules/resource-group"

  name     = var.resource_group_name
  location = var.azure_location
}

module "networking" {
  source = "./modules/networking"

  name                = var.name_prefix
  location            = var.azure_location
  resource_group_name = module.resource_group.name
}

module "storage" {
  source = "./modules/storage"

  name                = var.name_prefix
  location            = var.azure_location
  resource_group_name = module.resource_group.name
}

module "registry" {
  source = "./modules/registry"

  name                = var.name_prefix
  location            = var.azure_location
  resource_group_name = module.resource_group.name
  source_image        = "docker.io/${var.container_image}"
}

module "agent_pool" {
  source = "../modules/scalr/agent-pool"

  agent_pool_name = var.agent_pool_name
  webhook_url     = module.webhook.url
  webhook_headers = [
    {
      name      = "Content-Type"
      value     = "application/json"
      sensitive = false
    }
  ]
}

module "webhook" {
  source = "./modules/webhook"

  name                = var.name_prefix
  location            = var.azure_location
  resource_group_name = module.resource_group.name
  resource_group_id   = module.resource_group.id
  subscription_id     = data.azurerm_client_config.current.subscription_id
  allowed_ips         = module.scalr_ips.allowed_ips
  allow_all_ingress   = var.allow_all_ingress
  subnet_id           = module.networking.subnet_id
  container_image     = module.registry.image
  registry_server     = module.registry.login_server
  registry_username   = module.registry.admin_username
  registry_password   = module.registry.admin_password
  container_cpu       = var.container_cpu
  container_memory_gb = var.container_memory_gb
  scalr_url           = module.agent_pool.scalr_url
  scalr_agent_token   = module.agent_pool.agent_token
  storage_account_name       = module.storage.storage_account_name
  storage_account_key        = module.storage.storage_account_key
  terraform_cache_share_name = module.storage.terraform_cache_share_name
  providers_cache_share_name = module.storage.providers_cache_share_name
}
