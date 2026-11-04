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

locals {
  # Dedupe webhook deliveries on the Idempotency-Key header by claiming one
  # blob per key (create-if-absent is atomic in Blob Storage). APIM Consumption
  # has no built-in cache, so the storage account doubles as the key store.
  dedupe_enabled = var.storage_account_name != "" && var.idempotency_container_name != ""
  key_store_url  = "https://${var.storage_account_name}.blob.core.windows.net/${var.idempotency_container_name}/"
}

resource "azurerm_api_management_api_policy" "webhook" {
  api_name            = azurerm_api_management_api.webhook.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name

  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <set-variable name="idempotencyKey" value="@(context.Request.Headers.GetValueOrDefault("Idempotency-Key", "").Trim())" />
        <set-variable name="keyClaimed" value="@(false)" />
        <set-variable name="keyUrl" value="@("${local.key_store_url}" + System.Net.WebUtility.UrlEncode((string)context.Variables["idempotencyKey"]))" />
        <choose>
          <when condition="@(${local.dedupe_enabled} ? ((string)context.Variables["idempotencyKey"]).Length > 0 : false)">
            <!-- Claim the key: succeeds only if no blob exists for it yet. -->
            <send-request mode="new" response-variable-name="claimResponse" timeout="10" ignore-error="true">
              <set-url>@((string)context.Variables["keyUrl"])</set-url>
              <set-method>PUT</set-method>
              <set-header name="x-ms-version" exists-action="override">
                <value>2023-11-03</value>
              </set-header>
              <set-header name="x-ms-date" exists-action="override">
                <value>@(DateTime.UtcNow.ToString("R"))</value>
              </set-header>
              <set-header name="x-ms-blob-type" exists-action="override">
                <value>BlockBlob</value>
              </set-header>
              <set-header name="If-None-Match" exists-action="override">
                <value>*</value>
              </set-header>
              <set-header name="Content-Type" exists-action="override">
                <value>text/plain</value>
              </set-header>
              <set-body>@(DateTime.UtcNow.ToString("o"))</set-body>
              <authentication-managed-identity resource="https://storage.azure.com/" />
            </send-request>
            <set-variable name="claimStatus" value="@{
              var response = context.Variables.GetValueOrDefault<IResponse>("claimResponse");
              return response == null ? 0 : response.StatusCode;
            }" />
            <choose>
              <when condition="@((int)context.Variables["claimStatus"] == 201)">
                <set-variable name="keyClaimed" value="@(true)" />
              </when>
              <when condition="@((int)context.Variables["claimStatus"] == 409 || (int)context.Variables["claimStatus"] == 412)">
                <!-- The key is taken. Re-claim it only if the claim is older than the dedupe window. -->
                <send-request mode="new" response-variable-name="reclaimResponse" timeout="10" ignore-error="true">
                  <set-url>@((string)context.Variables["keyUrl"])</set-url>
                  <set-method>PUT</set-method>
                  <set-header name="x-ms-version" exists-action="override">
                    <value>2023-11-03</value>
                  </set-header>
                  <set-header name="x-ms-date" exists-action="override">
                    <value>@(DateTime.UtcNow.ToString("R"))</value>
                  </set-header>
                  <set-header name="x-ms-blob-type" exists-action="override">
                    <value>BlockBlob</value>
                  </set-header>
                  <set-header name="If-Unmodified-Since" exists-action="override">
                    <value>@(DateTime.UtcNow.AddMinutes(-${var.idempotency_window_minutes}).ToString("R"))</value>
                  </set-header>
                  <set-header name="Content-Type" exists-action="override">
                    <value>text/plain</value>
                  </set-header>
                  <set-body>@(DateTime.UtcNow.ToString("o"))</set-body>
                  <authentication-managed-identity resource="https://storage.azure.com/" />
                </send-request>
                <set-variable name="reclaimStatus" value="@{
                  var response = context.Variables.GetValueOrDefault<IResponse>("reclaimResponse");
                  return response == null ? 0 : response.StatusCode;
                }" />
                <choose>
                  <when condition="@((int)context.Variables["reclaimStatus"] == 201)">
                    <set-variable name="keyClaimed" value="@(true)" />
                  </when>
                  <otherwise>
                    <!-- Duplicate delivery: a job for this key was already started. -->
                    <return-response>
                      <set-status code="200" reason="OK" />
                      <set-header name="Content-Type" exists-action="override">
                        <value>application/json</value>
                      </set-header>
                      <set-body>@(new JObject(
                        new JProperty("status", "duplicate"),
                        new JProperty("idempotencyKey", (string)context.Variables["idempotencyKey"])
                      ).ToString())</set-body>
                    </return-response>
                  </otherwise>
                </choose>
              </when>
              <otherwise>
                <!-- Key store unavailable: fail so that Scalr retries. -->
                <return-response>
                  <set-status code="503" reason="Service Unavailable" />
                  <set-header name="Content-Type" exists-action="override">
                    <value>application/json</value>
                  </set-header>
                  <set-body>@(new JObject(
                    new JProperty("status", "error"),
                    new JProperty("message", "Could not claim the idempotency key"),
                    new JProperty("keyStoreStatus", (int)context.Variables["claimStatus"])
                  ).ToString())</set-body>
                </return-response>
              </otherwise>
            </choose>
          </when>
        </choose>
        <send-request mode="new" response-variable-name="jobResponse" timeout="30" ignore-error="true">
          <set-url>https://management.azure.com${azurerm_container_app_job.scalr_agent.id}/start?api-version=2024-03-01</set-url>
          <set-method>POST</set-method>
          <set-header name="Content-Type" exists-action="override">
            <value>application/json</value>
          </set-header>
          <set-body>{}</set-body>
          <authentication-managed-identity resource="https://management.azure.com/" />
        </send-request>
        <set-variable name="jobStatus" value="@{
          var response = context.Variables.GetValueOrDefault<IResponse>("jobResponse");
          return response == null ? 0 : response.StatusCode;
        }" />
        <choose>
          <when condition="@((int)context.Variables["jobStatus"] / 100 == 2)">
            <return-response response-variable-name="jobResponse" />
          </when>
          <otherwise>
            <!-- The job did not start: release the key so that the retry can start it. -->
            <choose>
              <when condition="@((bool)context.Variables["keyClaimed"])">
                <send-request mode="new" response-variable-name="releaseResponse" timeout="10" ignore-error="true">
                  <set-url>@((string)context.Variables["keyUrl"])</set-url>
                  <set-method>DELETE</set-method>
                  <set-header name="x-ms-version" exists-action="override">
                    <value>2023-11-03</value>
                  </set-header>
                  <set-header name="x-ms-date" exists-action="override">
                    <value>@(DateTime.UtcNow.ToString("R"))</value>
                  </set-header>
                  <authentication-managed-identity resource="https://storage.azure.com/" />
                </send-request>
              </when>
            </choose>
            <choose>
              <when condition="@((int)context.Variables["jobStatus"] == 0)">
                <return-response>
                  <set-status code="504" reason="Gateway Timeout" />
                  <set-header name="Content-Type" exists-action="override">
                    <value>application/json</value>
                  </set-header>
                  <set-body>{"status": "error", "message": "The Container Apps Job start request failed"}</set-body>
                </return-response>
              </when>
              <otherwise>
                <return-response response-variable-name="jobResponse" />
              </otherwise>
            </choose>
          </otherwise>
        </choose>
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

resource "azurerm_role_assignment" "apim_idempotency_keys" {
  count                = local.dedupe_enabled ? 1 : 0
  scope                = var.idempotency_container_id
  role_definition_name = "Storage Blob Data Contributor"
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
