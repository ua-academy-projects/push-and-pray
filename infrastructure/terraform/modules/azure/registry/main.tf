variable "config" {
  type = any
}

variable "resource_group_name" {
  type = string
}

data "azurerm_client_config" "current" {}

locals {
  region = var.config.locations[var.config.default_location].azure.region
  name   = substr("${replace("${var.config.name_prefix}${var.config.environment}", "-", "")}${substr(sha1(data.azurerm_client_config.current.subscription_id), 0, 8)}", 0, 50)
}

resource "azurerm_container_registry" "app" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = local.region
  sku                 = "Basic"
  admin_enabled       = false
  tags                = merge(var.config.common_labels, { environment = var.config.environment })
}

resource "azurerm_role_assignment" "publisher" {
  scope                = azurerm_container_registry.app.id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
}

output "registry" {
  value = {
    cloud  = "azure"
    name   = azurerm_container_registry.app.name
    region = local.region
    server = azurerm_container_registry.app.login_server
    images = {
      for image in ["history", "fetcher", "ui", "database-cnpg"] : image => "${azurerm_container_registry.app.login_server}/oilscope/${image}"
    }
  }
}
