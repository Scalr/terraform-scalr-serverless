# Logic App receives the Scalr webhook and starts a Container Apps Job execution.
# Starting a job is near-instant (~5s cold start) compared to creating an ACI container (~2min).

resource "azurerm_logic_app_workflow" "this" {
  name                = "${var.name}-webhook"
  location            = var.location
  resource_group_name = var.resource_group_name

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_logic_app_trigger_http_request" "this" {
  name         = "scalr-webhook"
  logic_app_id = azurerm_logic_app_workflow.this.id

  schema = jsonencode({
    type = "object"
  })
}

resource "azurerm_logic_app_action_custom" "start_job" {
  name         = "start-container-app-job"
  logic_app_id = azurerm_logic_app_workflow.this.id

  body = jsonencode({
    type = "Http"
    inputs = {
      method = "POST"
      uri    = "https://management.azure.com${azurerm_container_app_job.scalr_agent.id}/start?api-version=2024-03-01"
      authentication = {
        type = "ManagedServiceIdentity"
      }
      headers = {
        "Content-Type" = "application/json"
      }
      body = {}
    }
    runAfter = {}
  })
}

resource "azurerm_role_assignment" "job_contributor" {
  scope                = azurerm_container_app_job.scalr_agent.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_logic_app_workflow.this.identity[0].principal_id
}

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
