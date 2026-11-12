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
          <set-body>@{
            // Scalr sends agent options, such as SCALR_AGENT_TASK_ID, with each webhook.
            JObject options = null;
            try {
              options = context.Request.Body.As<JObject>(preserveContent: true)["agent_environment"] as JObject;
            } catch {
              return "{}";
            }
            if (options == null) {
              return "{}";
            }

            var allowed = new JArray();
            foreach (var option in options.Properties()) {
              if (option.Value.Type != JTokenType.String) { continue; }
              if (!Regex.IsMatch(option.Name, "^SCALR_AGENT_[A-Z0-9_]+$")) { continue; }
              if (option.Name == "SCALR_AGENT_TOKEN" || option.Name == "SCALR_AGENT_SINGLE") { continue; }
              allowed.Add(new JObject(new JProperty("name", option.Name), new JProperty("value", (string)option.Value)));
            }
            if (allowed.Count == 0) {
              return "{}";
            }

            // A start override replaces the job's container, so it repeats the whole container.
            var container = JObject.Parse(Encoding.UTF8.GetString(Convert.FromBase64String("${base64encode(jsonencode(local.agent_container))}")));
            var env = (JArray)container["env"];
            foreach (JObject item in allowed) {
              foreach (var existing in env.Where(e => (string)e["name"] == (string)item["name"]).ToList()) {
                existing.Remove();
              }
              env.Add(item);
            }
            return new JObject(new JProperty("containers", new JArray(container))).ToString(Newtonsoft.Json.Formatting.None);
          }</set-body>
          <authentication-managed-identity resource="https://management.azure.com/" />
        </send-request>
        <return-response response-variable-name="job-response">
          <set-header name="Scalr-Launcher-Version" exists-action="override">
            <value>${local.launcher_version}</value>
          </set-header>
        </return-response>
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

  # var.agent_environment overrides these defaults; its validation keeps the token and single-run mode.
  agent_environment = merge(
    {
      SCALR_URL              = var.scalr_url
      SCALR_AGENT_SINGLE     = "true"
      SCALR_AGENT_DRIVER     = "local"
      SCALR_AGENT_LOG_FORMAT = "json"
    },
    local.use_file_cache ? {
      TF_PLUGIN_CACHE_DIR = "/terraform-cache"
      TF_DATA_DIR         = "/providers-cache"
    } : {},
    var.agent_environment,
  )

  # The agent container as the Container Apps API describes it. A job start with agent options
  # from the webhook sends it as an override, which replaces the job's container, so it must
  # match the template of azurerm_container_app_job.scalr_agent.
  agent_container = {
    name  = "scalr-agent"
    image = var.container_image
    resources = {
      cpu    = var.container_cpu
      memory = "${var.container_memory_gb}Gi"
    }
    env = concat(
      [{ name = "SCALR_AGENT_TOKEN", secretRef = "scalr-token" }],
      [for name, value in local.agent_environment : { name = name, value = value }],
    )
    volumeMounts = local.use_file_cache ? [
      { volumeName = "terraform-cache", mountPath = "/terraform-cache" },
      { volumeName = "providers-cache", mountPath = "/providers-cache" },
    ] : []
  }

  # Reported to Scalr in the Scalr-Launcher-Version response header. Bump it with each release.
  launcher_version = "0.1.0"
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

  # Keep in sync with local.agent_container, which webhook starts with agent options send instead.
  template {
    container {
      name   = local.agent_container.name
      image  = local.agent_container.image
      cpu    = local.agent_container.resources.cpu
      memory = local.agent_container.resources.memory

      env {
        name        = "SCALR_AGENT_TOKEN"
        secret_name = "scalr-token"
      }

      dynamic "env" {
        for_each = local.agent_environment
        content {
          name  = env.key
          value = env.value
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
