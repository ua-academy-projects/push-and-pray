output "endpoint" {
  value = try(azurerm_postgresql_flexible_server.main[0].fqdn, null)
}