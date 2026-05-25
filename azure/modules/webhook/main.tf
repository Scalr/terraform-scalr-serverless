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

locals {
  use_registry   = var.registry_server != ""
  use_file_cache = var.storage_account_name != ""

  container_environment_variables = concat(
    [
      { name = "SCALR_URL", value = var.scalr_url },
      { name = "SCALR_TOKEN", secureValue = var.scalr_agent_token },
      { name = "SCALR_SINGLE", value = "true" },
      { name = "SCALR_DRIVER", value = "local" },
    ],
    local.use_file_cache ? [
      { name = "TF_PLUGIN_CACHE_DIR", value = "/terraform-cache" },
      { name = "TF_DATA_DIR", value = "/providers-cache" },
    ] : []
  )

  container_volume_mounts = local.use_file_cache ? [
    { name = "terraform-cache", mountPath = "/terraform-cache" },
    { name = "providers-cache", mountPath = "/providers-cache" },
  ] : []

  aci_volumes = local.use_file_cache ? [
    {
      name = "terraform-cache"
      azureFile = {
        shareName           = var.terraform_cache_share_name
        storageAccountName  = var.storage_account_name
        storageAccountKey   = var.storage_account_key
        readOnly            = false
      }
    },
    {
      name = "providers-cache"
      azureFile = {
        shareName           = var.providers_cache_share_name
        storageAccountName  = var.storage_account_name
        storageAccountKey   = var.storage_account_key
        readOnly            = false
      }
    },
  ] : []

  aci_properties = merge(
    {
      osType        = "Linux"
      restartPolicy = "Never"
      containers = [
        {
          name = "scalr-agent"
          properties = {
            image = var.container_image
            resources = {
              requests = {
                cpu         = var.container_cpu
                memoryInGB  = var.container_memory_gb
              }
            }
            environmentVariables = local.container_environment_variables
            volumeMounts         = local.container_volume_mounts
          }
        },
      ]
    },
    var.subnet_id != "" ? { subnetIds = [{ id = var.subnet_id }] } : {},
    local.use_file_cache ? { volumes = local.aci_volumes } : {},
    local.use_registry ? {
      imageRegistryCredentials = [{
        server   = var.registry_server
        username = var.registry_username
        password = var.registry_password
      }]
    } : {},
  )

  aci_request_body = jsonencode({
    location   = var.location
    properties = local.aci_properties
  })
}

# HTTP action with Managed Identity is not supported on azurerm_logic_app_action_http;
# use a custom action so the workflow can call the Azure Resource Manager API.
resource "azurerm_logic_app_action_custom" "create_aci" {
  name         = "create-container-group"
  logic_app_id = azurerm_logic_app_workflow.this.id

  body = jsonencode({
    type = "Http"
    inputs = {
      method = "PUT"
      uri    = "https://management.azure.com/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.ContainerInstance/containerGroups/scalr-agent-@{guid()}?api-version=2023-05-01"
      authentication = {
        type = "ManagedServiceIdentity"
      }
      headers = {
        "Content-Type" = "application/json"
      }
      body = jsondecode(local.aci_request_body)
    }
    runAfter = {}
  })
}

resource "azurerm_role_assignment" "aci_contributor" {
  scope                = var.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_logic_app_workflow.this.identity[0].principal_id
}
