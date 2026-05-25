resource "azurerm_storage_account" "cache" {
  name                     = substr(replace(lower("${var.name}cache"), "-", ""), 0, 24)
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_share" "terraform_cache" {
  name                = "terraform-cache"
  storage_account_id  = azurerm_storage_account.cache.id
  quota               = 50
}

resource "azurerm_storage_share" "providers_cache" {
  name                = "providers-cache"
  storage_account_id  = azurerm_storage_account.cache.id
  quota               = 50
}
