resource "random_password" "db" {
  count   = local.enabled ? 1 : 0
  length  = 32
  special = false
}

resource "azurerm_private_dns_zone" "postgres" {
  count = local.enabled ? 1 : 0

  name                = "${local.resource_prefix}.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count = local.enabled ? 1 : 0

  name                  = "${local.resource_prefix}-pg-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = var.vnet_id
}

resource "azurerm_postgresql_flexible_server" "main" {
  count = local.enabled ? 1 : 0

  name                = "${local.resource_prefix}-postgres"
  resource_group_name = var.resource_group_name
  location            = var.location

  version                = var.config.managed_db.version.azure
  sku_name               = var.config.managed_db.tier.azure
  storage_mb             = max(var.config.managed_db.disk_size_gb * 1024, 32768)
  administrator_login    = local.db_user
  administrator_password = random_password.db[0].result

  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres[0].id
  public_network_access_enabled = false

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  count = local.enabled ? 1 : 0

  name      = local.db_name
  server_id = azurerm_postgresql_flexible_server.main[0].id
}

resource "azurerm_key_vault_secret" "db_password" {
  count = local.enabled ? 1 : 0

  name         = var.postgres_password_secret_id
  value        = random_password.db[0].result
  key_vault_id = var.key_vault_id
}