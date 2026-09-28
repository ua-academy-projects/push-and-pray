output "hostname" {
  description = "Private DNS hostname for PostgreSQL."
  value       = "${azurerm_private_dns_cname_record.postgresql.name}.${azurerm_private_dns_zone.internal.name}"
}

output "resource_id" {
  description = "Azure Database for PostgreSQL Flexible Server resource ID."
  value       = azurerm_postgresql_flexible_server.this.id
}
