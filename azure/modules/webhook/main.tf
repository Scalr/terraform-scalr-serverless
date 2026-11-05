# API Management (Consumption) receives the Scalr webhook, authenticates via
# subscription key, and starts a Container Apps Job execution using managed identity.

resource "azurerm_api_management" "this" {
  name                = "${var.name}-apim"
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = "Scalr"
  publisher_email     = "noreply@scalr.com"
  sku_name            = "Consumption_0"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_api_management_api" "webhook" {
  name                  = "scalr-webhook"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Scalr Webhook"
  path                  = "webhook"
  protocols             = ["https"]
  subscription_required = true
}

resource "azurerm_api_management_api_operation" "trigger" {
  operation_id        = "trigger-agent"
  api_name            = azurerm_api_management_api.webhook.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "Trigger Agent"
  method              = "POST"
  url_template        = "/"
}

resource "azurerm_api_management_api_policy" "webhook" {
  api_name            = azurerm_api_management_api.webhook.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name

  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <send-request mode="new" response-variable-name="job-response" timeout="30" ignore-error="false">
          <set-url>https://management.azure.com${azurerm_container_app_job.scalr_agent.id}/start?api-version=2024-03-01</set-url>
          <set-method>POST</set-method>
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>{}</set-body>
          <authentication-managed-identity resource="https://management.azure.com/" />
        </send-request>
        <return-response response-variable-name="job-response" />
      </inbound>
    </policies>
  XML
}

resource "azurerm_api_management_subscription" "webhook" {
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = "Scalr Webhook"
  state               = "active"
}

resource "azurerm_role_assignment" "apim_job_contributor" {
  scope                = azurerm_container_app_job.scalr_agent.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

# --- Container Apps Environment & Job ---

resource "azurerm_container_app_environment" "this" {
  name                = "${var.name}-env"
  location            = var.location
  resource_group_name = var.resource_group_name

  infrastructure_subnet_id = var.subnet_id != "" ? var.subnet_id : null
}

resource "azurerm_container_app_environment_storage" "terraform_cache" {
  count                        = var.storage_account_name != "" ? 1 : 0
  name                         = "terraform-cache"
  container_app_environment_id = azurerm_container_app_environment.this.id
  account_name                 = var.storage_account_name
  share_name                   = var.terraform_cache_share_name
  access_key                   = var.storage_account_key
  access_mode                  = "ReadWrite"
}

resource "azurerm_container_app_environment_storage" "providers_cache" {
  count                        = var.storage_account_name != "" ? 1 : 0
  name                         = "providers-cache"
  container_app_environment_id = azurerm_container_app_environment.this.id
  account_name                 = var.storage_account_name
  share_name                   = var.providers_cache_share_name
  access_key                   = var.storage_account_key
  access_mode                  = "ReadWrite"
}

locals {
  use_file_cache = var.storage_account_name != ""
  use_registry   = var.registry_server != ""
}

resource "azurerm_container_app_job" "scalr_agent" {
  name                         = "${var.name}-agent"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id

  replica_timeout_in_seconds = var.job_timeout
  replica_retry_limit        = 0

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  dynamic "registry" {
    for_each = local.use_registry ? [1] : []
    content {
      server               = var.registry_server
      username             = var.registry_username
      password_secret_name = "registry-password"
    }
  }

  secret {
    name  = "scalr-token"
    value = var.scalr_agent_token
  }

  dynamic "secret" {
    for_each = local.use_registry ? [1] : []
    content {
      name  = "registry-password"
      value = var.registry_password
    }
  }

  template {
    container {
      name   = "scalr-agent"
      image  = var.container_image
      cpu    = var.container_cpu
      memory = "${var.container_memory_gb}Gi"

      env {
        name  = "SCALR_URL"
        value = var.scalr_url
      }

      env {
        name        = "SCALR_TOKEN"
        secret_name = "scalr-token"
      }

      env {
        name  = "SCALR_SINGLE"
        value = "true"
      }

      env {
        name  = "SCALR_DRIVER"
        value = "local"
      }

      dynamic "env" {
        for_each = local.use_file_cache ? [1] : []
        content {
          name  = "TF_PLUGIN_CACHE_DIR"
          value = "/terraform-cache"
        }
      }

      dynamic "env" {
        for_each = local.use_file_cache ? [1] : []
        content {
          name  = "TF_DATA_DIR"
          value = "/providers-cache"
        }
      }

      dynamic "volume_mounts" {
        for_each = local.use_file_cache ? [1] : []
        content {
          name = "terraform-cache"
          path = "/terraform-cache"
        }
      }

      dynamic "volume_mounts" {
        for_each = local.use_file_cache ? [1] : []
        content {
          name = "providers-cache"
          path = "/providers-cache"
        }
      }
    }

    dynamic "volume" {
      for_each = local.use_file_cache ? [1] : []
      content {
        name         = "terraform-cache"
        storage_name = azurerm_container_app_environment_storage.terraform_cache[0].name
        storage_type = "AzureFile"
      }
    }

    dynamic "volume" {
      for_each = local.use_file_cache ? [1] : []
      content {
        name         = "providers-cache"
        storage_name = azurerm_container_app_environment_storage.providers_cache[0].name
        storage_type = "AzureFile"
      }
    }
  }
}
