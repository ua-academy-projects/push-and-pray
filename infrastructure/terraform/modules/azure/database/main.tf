resource "azurerm_postgresql_flexible_server" "this" {
  count = local.enabled ? 1 : 0

  name                = "${local.resource_prefix}-database"
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  version             = local.settings.postgres_version
  zone                = local.zone
  tags                = local.tags

  delegated_subnet_id           = var.network.postgres.subnet_id
  private_dns_zone_id           = var.network.postgres.private_dns_zone_id
  public_network_access_enabled = false

  administrator_login    = local.admin_username
  administrator_password = random_password.admin[0].result

  sku_name                     = local.settings.sku_name
  storage_mb                   = local.settings.storage_mb
  storage_tier                 = local.settings.storage_tier
  auto_grow_enabled            = false
  backup_retention_days        = local.settings.backup_retention_days
  geo_redundant_backup_enabled = false

  dynamic "high_availability" {
    for_each = local.settings.high_availability == "Disabled" ? [] : [local.settings.high_availability]

    content {
      mode                      = high_availability.value
      standby_availability_zone = local.settings.standby_availability_zone
    }
  }
}

resource "azurerm_postgresql_flexible_server_configuration" "require_secure_transport" {
  count = local.enabled ? 1 : 0

  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.this[0].id
  value     = "on"
}

resource "azurerm_postgresql_flexible_server_database" "application" {
  count = local.enabled ? 1 : 0

  name      = "oil_tracker"
  server_id = azurerm_postgresql_flexible_server.this[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
