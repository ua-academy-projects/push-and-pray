output "database" {
  description = "Non-secret private PostgreSQL Flexible Server connection metadata."
  value = local.enabled ? {
    provider            = "azure"
    host                = azurerm_postgresql_flexible_server.postgres[0].fqdn
    port                = var.config.database.port
    name                = azurerm_postgresql_flexible_server_database.application[0].name
    admin_user          = var.config.database.admin_user
    admin_secret_arn    = null
    instance_name       = azurerm_postgresql_flexible_server.postgres[0].name
    sslmode             = "require"
    publicly_accessible = false
  } : null
}

output "enabled" {
  value = local.enabled
}
