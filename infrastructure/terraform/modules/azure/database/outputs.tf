output "connection" {
  description = "Flexible Server connection metadata and administrator secret reference; null when disabled. Never contains password values."
  value = local.enabled ? {
    host                = azurerm_postgresql_flexible_server.this[0].fqdn
    port                = 5432
    database            = azurerm_postgresql_flexible_server_database.application[0].name
    admin_username      = azurerm_postgresql_flexible_server.this[0].administrator_login
    admin_secret_id     = azurerm_key_vault_secret.admin[0].versionless_id
    sslmode             = "verify-full"
    ca_bundle_url       = null
    ca_certificate_urls = local.ca_certificate_urls
  } : null
  depends_on = [azurerm_postgresql_flexible_server_configuration.require_secure_transport]
}

output "monitoring" {
  value = local.enabled ? {
    id = azurerm_postgresql_flexible_server.this[0].id
  } : null
}
