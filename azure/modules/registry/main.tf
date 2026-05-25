locals {
  # e.g. "docker.io/scalr/agent:latest" → "scalr/agent:latest"
  image_ref = replace(var.source_image, "docker.io/", "")
}

resource "azurerm_container_registry" "this" {
  name                          = substr(replace(lower("${var.name}acr"), "-", ""), 0, 50)
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = "Basic"
  admin_enabled                 = true
  public_network_access_enabled = true
  # checkov:skip=CKV_AZURE_137:Admin account required for Container Apps registry auth
  # checkov:skip=CKV_AZURE_139:Public network needed — private endpoint requires Premium SKU
  # checkov:skip=CKV_AZURE_163:Vulnerability scanning requires Microsoft Defender for Containers
  # checkov:skip=CKV_AZURE_164:Content trust requires Premium SKU
  # checkov:skip=CKV_AZURE_165:Geo-replication requires Premium SKU
  # checkov:skip=CKV_AZURE_166:Quarantine requires Premium SKU
  # checkov:skip=CKV_AZURE_167:Retention policy requires Basic or higher but is not critical for a mirror registry
  # checkov:skip=CKV_AZURE_233:Zone redundancy requires Premium SKU
  # checkov:skip=CKV_AZURE_237:Dedicated data endpoints require Premium SKU
}

# Import the image from Docker Hub into ACR so ACI pulls within Azure's network.
resource "terraform_data" "import_image" {
  triggers_replace = [
    azurerm_container_registry.this.login_server,
    var.source_image,
  ]

  provisioner "local-exec" {
    command = "az acr import --name ${azurerm_container_registry.this.name} --source ${var.source_image} --image ${local.image_ref} --force"
  }
}
