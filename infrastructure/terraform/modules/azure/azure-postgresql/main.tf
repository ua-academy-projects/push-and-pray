data "azurerm_client_config" "current" {
  count = var.enabled ? 1 : 0
}

resource "random_string" "suffix" {
  count = var.enabled ? 1 : 0

  length  = 6
  upper   = false
  special = false
}

resource "random_password" "database" {
  count = var.enabled ? 1 : 0

  length  = 32
  special = false
}

locals {
  suffix      = try(random_string.suffix[0].result, "")
  server_name = substr("${var.name_prefix}-postgres-${local.suffix}", 0, 63)
  vault_name  = substr(replace(lower("${var.name_prefix}kv${local.suffix}"), "-", ""), 0, 24)
  common_tags = merge(var.tags, {
    managed_by = "terraform"
    service    = "postgresql"
    cloud      = "azure"
  })
}

resource "azurerm_private_dns_zone" "postgresql" {
  count = var.enabled ? 1 : 0

  name                = "${local.server_name}.private.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  for_each = var.enabled ? var.virtual_network_ids : {}

  name                  = substr(replace("${var.name_prefix}-postgres-${each.key}-vnet-link", "_", "-"), 0, 80)
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgresql[0].name
  virtual_network_id    = each.value
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_postgresql_flexible_server" "this" {
  count = var.enabled ? 1 : 0

  name                          = local.server_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = var.database_version
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.postgresql[0].id
  public_network_access_enabled = false
  administrator_login           = var.username
  administrator_password        = random_password.database[0].result
  zone                          = var.zone
  storage_mb                    = var.storage_mb
  sku_name                      = var.sku_name
  backup_retention_days         = var.backup_retention_days
  tags                          = local.common_tags

  lifecycle {
    precondition {
      condition     = var.clients_share_cloud
      error_message = "Azure PostgreSQL clients must all select Azure until private cross-cloud routing exists."
    }
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  count = var.enabled ? 1 : 0

  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.this[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_key_vault" "database" {
  count = var.enabled ? 1 : 0

  name                       = local.vault_name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current[0].tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = local.common_tags
}

resource "azurerm_key_vault_access_policy" "terraform" {
  count = var.enabled ? 1 : 0

  key_vault_id = azurerm_key_vault.database[0].id
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
  for_each = var.enabled ? var.identity_principal_ids : {}

  key_vault_id = azurerm_key_vault.database[0].id
  tenant_id    = data.azurerm_client_config.current[0].tenant_id
  object_id    = each.value
  secret_permissions = [
    "Get",
    "List",
  ]
}

resource "azurerm_key_vault_secret" "credentials" {
  count = var.enabled ? 1 : 0

  name         = "managed-database"
  key_vault_id = azurerm_key_vault.database[0].id
  value = jsonencode({
    username = var.username
    password = random_password.database[0].result
    host     = azurerm_postgresql_flexible_server.this[0].fqdn
    port     = 5432
    dbname   = var.database_name
  })

  depends_on = [azurerm_key_vault_access_policy.terraform]
}
