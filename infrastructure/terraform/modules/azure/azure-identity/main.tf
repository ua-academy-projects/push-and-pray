locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  common_tags = merge(var.config.common_labels, {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = "azure"
  })
  application_secret_ids = toset(flatten([
    for vm in values(var.vms) : values(lookup(vm, "secret_mappings", {}))
  ]))
}

data "azurerm_client_config" "current" {
  count = length(var.vms) > 0 ? 1 : 0
}

resource "random_string" "vault_suffix" {
  count = length(var.vms) > 0 ? 1 : 0

  length  = 6
  upper   = false
  special = false
}

resource "random_password" "generated" {
  for_each = var.generated_secret_ids

  length  = 32
  special = false

  lifecycle {
    precondition {
      condition     = contains(local.application_secret_ids, each.key)
      error_message = "Every generated Azure secret ID must exist in a workload secret mapping."
    }
  }
}

resource "azurerm_user_assigned_identity" "vm" {
  for_each = var.vms

  name                = "${local.resource_prefix}-${each.key}-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(local.common_tags, { role = each.value.role })
}

resource "azurerm_key_vault" "application" {
  count = length(var.vms) > 0 ? 1 : 0

  name = substr(
    replace(lower("${local.resource_prefix}app${random_string.vault_suffix[0].result}"), "-", ""),
    0,
    24,
  )
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current[0].tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = merge(local.common_tags, { service = "application-secrets" })
}

resource "azurerm_key_vault_access_policy" "terraform" {
  count = length(var.vms) > 0 ? 1 : 0

  key_vault_id = azurerm_key_vault.application[0].id
  tenant_id    = data.azurerm_client_config.current[0].tenant_id
  object_id    = data.azurerm_client_config.current[0].object_id
  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Recover",
    "Purge",
  ]
}

resource "azurerm_key_vault_access_policy" "vm" {
  for_each = azurerm_user_assigned_identity.vm

  key_vault_id = azurerm_key_vault.application[0].id
  tenant_id    = data.azurerm_client_config.current[0].tenant_id
  object_id    = each.value.principal_id
  secret_permissions = [
    "Get",
    "List",
  ]
}

resource "azurerm_key_vault_secret" "generated" {
  for_each = var.generated_secret_ids

  name         = each.key
  key_vault_id = azurerm_key_vault.application[0].id
  value        = random_password.generated[each.key].result

  depends_on = [azurerm_key_vault_access_policy.terraform]
}
