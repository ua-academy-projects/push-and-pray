data "azurerm_client_config" "current" {}

resource "random_string" "kv_suffix" {
  count   = var.has_selected_vms ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_key_vault" "this" {
  count = var.has_selected_vms ? 1 : 0

  name                = "${local.resource_prefix}-kv-${random_string.kv_suffix[0].result}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  access_policy {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    object_id          = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
  }

  dynamic "access_policy" {
    for_each = local.workload_vms
    content {
      tenant_id          = data.azurerm_client_config.current.tenant_id
      object_id          = var.principal_ids[access_policy.key]
      secret_permissions = ["Get"]
    }
  }

  dynamic "access_policy" {
    for_each = toset(var.azure_secret_version_managers)
    content {
      tenant_id          = data.azurerm_client_config.current.tenant_id
      object_id          = access_policy.value
      secret_permissions = ["Get", "List", "Set"]
    }
  }
}
