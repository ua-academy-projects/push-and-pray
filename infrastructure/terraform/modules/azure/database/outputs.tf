output "host" {
  value = azurerm_postgresql_flexible_server.postgres.fqdn
}

output "port" {
  value = var.database.port
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.application.name
}

output "username" {
  value = azurerm_postgresql_flexible_server.postgres.administrator_login
}

output "server_id" {
  value = azurerm_postgresql_flexible_server.postgres.id
}
