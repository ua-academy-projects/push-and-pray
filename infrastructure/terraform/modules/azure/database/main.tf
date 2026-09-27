resource "azurerm_postgresql_flexible_server" "postgres" {
  name = substr(
    "${var.resource_prefix}-postgres-${substr(sha256(var.resource_group_name), 0, 6)}",
    0,
    63,
  )

  resource_group_name = var.resource_group_name
  location            = var.location
  zone                = var.zone
  version             = var.managed_settings.version
  sku_name            = var.managed_settings.sku_name

  administrator_login    = var.database.user
  administrator_password = var.administrator_password

  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = false

  storage_mb                   = 32768
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  tags                         = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "application" {
  name      = var.database.name
  server_id = azurerm_postgresql_flexible_server.postgres.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
