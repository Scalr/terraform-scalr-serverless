terraform {
  required_providers {
    scalr = {
      source  = "scalr/scalr"
    }
  }
}

data "scalr_current_account" "this" {}

resource "scalr_agent_pool" "webhook" {
  name = var.agent_pool_name

  api_gateway_url = var.webhook_url

  dynamic "header" {
    for_each = var.webhook_url != null ? var.webhook_headers : []
    content {
      name      = header.value.name
      value     = header.value.value
      sensitive = header.value.sensitive
    }
  }
}

resource "scalr_agent_pool_token" "webhook" {
  agent_pool_id = scalr_agent_pool.webhook.id
  description   = "Token for Scalr webhook agent"
}

locals {
  scalr_url = "https://${data.scalr_current_account.this.name}.scalr.io"
}