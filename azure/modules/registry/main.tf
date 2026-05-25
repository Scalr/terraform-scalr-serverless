locals {
  # e.g. "docker.io/scalr/agent:latest" → "scalr/agent:latest"
  image_ref = replace(var.source_image, "docker.io/", "")
}

resource "azurerm_container_registry" "this" {
  name                = substr(replace(lower("${var.name}acr"), "-", ""), 0, 50)
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = true
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
