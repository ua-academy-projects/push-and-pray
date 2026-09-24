data "azurerm_client_config" "current" {
  count = local.enabled ? 1 : 0
}

resource "azurerm_key_vault" "main" {
  count = local.enabled ? 1 : 0

  name                = local.vault_name
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  tenant_id           = data.azurerm_client_config.current[0].tenant_id
  sku_name            = "standard"
  tags                = local.common_tags

  rbac_authorization_enabled    = true
  public_network_access_enabled = true

  soft_delete_retention_days = local.settings.soft_delete_retention_days
  purge_protection_enabled   = local.settings.purge_protection_enabled
}

resource "azurerm_role_assignment" "workload_secret_access" {
  for_each = { for pair in local.workload_secret_pairs : "${pair.vm_name}/${pair.secret_id}" => pair }

  scope                = "${azurerm_key_vault.main[0].id}/secrets/${each.value.secret_id}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.vms[each.value.vm_name].identity_principal_id
}

resource "azurerm_role_assignment" "deployer" {
  count = local.database_enabled ? 1 : 0

  scope                = azurerm_key_vault.main[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current[0].object_id
}

resource "azurerm_role_assignment" "version_manager" {
  for_each = local.enabled ? toset(var.secret_version_managers) : toset([])

  scope                = azurerm_key_vault.main[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}
