resource "azurerm_storage_account" "cache" {
  # checkov:skip=CKV_AZURE_59:Public network access required — ACA mounts Azure Files over SMB
  # checkov:skip=CKV_AZURE_206:GRS replication unnecessary for a disposable Terraform cache
  # checkov:skip=CKV2_AZURE_1:CMK encryption not warranted for ephemeral provider/module cache
  # checkov:skip=CKV2_AZURE_33:Private endpoint adds complexity not justified for cache storage
  # checkov:skip=CKV2_AZURE_40:Shared Key auth required for ACA environment storage mounts
  # checkov:skip=CKV2_AZURE_41:SAS tokens not used — expiration policy set but checkov may not detect it
  name                          = substr(replace(lower("${var.name}cache"), "-", ""), 0, 24)
  resource_group_name           = var.resource_group_name
  location                      = var.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  min_tls_version               = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  sas_policy {
    expiration_period = "90.00:00:00"
  }

}

resource "azurerm_storage_account_queue_properties" "cache" {
  storage_account_id = azurerm_storage_account.cache.id

  logging {
    delete                = true
    read                  = true
    write                 = true
    version               = "1.0"
    retention_policy_days = 7
  }
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
