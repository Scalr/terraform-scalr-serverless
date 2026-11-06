# Plan-only tests of the webhook module with a mocked provider: no Azure credentials needed.

mock_provider "azurerm" {
  # The provider parses these IDs even when the values come from mocks.
  mock_resource "azurerm_container_app_environment" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/scalr-serverless-rg/providers/Microsoft.App/managedEnvironments/scalr-agent-env" }
  }

  mock_resource "azurerm_container_app_job" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/scalr-serverless-rg/providers/Microsoft.App/jobs/scalr-agent-agent" }
  }
}

variables {
  name                = "scalr-agent"
  location            = "eastus"
  resource_group_name = "scalr-serverless-rg"
  container_image     = "scalr/agent:latest"
  scalr_url           = "https://example.scalr.io"
  scalr_agent_token   = "token"
}

run "webhook_starts_a_single_run_agent" {
  command = plan

  module {
    source = "./modules/webhook"
  }

  assert {
    condition     = azurerm_api_management_api.webhook.subscription_required
    error_message = "The webhook API must require a subscription key."
  }

  assert {
    condition = anytrue([
      for env in azurerm_container_app_job.scalr_agent.template[0].container[0].env :
      env.name == "SCALR_AGENT_SINGLE" && env.value == "true"
    ])
    error_message = "The agent must run in single-run mode."
  }

  assert {
    condition     = length(azurerm_container_app_environment_storage.terraform_cache) == 0
    error_message = "Without a storage account, the job must not mount the cache."
  }
}

run "storage_account_enables_the_cache" {
  command = plan

  module {
    source = "./modules/webhook"
  }

  variables {
    storage_account_name       = "scalragentcache"
    storage_account_key        = "key"
    terraform_cache_share_name = "terraform-cache"
    providers_cache_share_name = "providers-cache"
  }

  assert {
    condition     = length(azurerm_container_app_job.scalr_agent.template[0].volume) == 2
    error_message = "With a storage account, the job must mount both cache shares."
  }
}
