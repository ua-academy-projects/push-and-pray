data "azurerm_client_config" "current" {
  for_each = local.shared_resources
}

resource "azurerm_user_assigned_identity" "vm" {
  for_each = local.vms

  name                = "${local.resource_prefix}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_key_vault" "this" {
  for_each = local.shared_resources

  name                       = local.key_vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current[each.key].tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = local.tags
}

resource "azurerm_role_assignment" "vm_secret_reader" {
  for_each = local.identities_requiring_secrets

  scope                = azurerm_key_vault.this["main"].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.vm[each.key].principal_id
}

resource "azurerm_role_assignment" "deployer_secret_officer" {
  for_each = local.shared_resources

  scope                = azurerm_key_vault.this[each.key].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current[each.key].object_id
}
