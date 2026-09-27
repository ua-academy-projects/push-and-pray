output "fqdn" {
  value = try(azurerm_postgresql_flexible_server.this[0].fqdn, null)
}

output "port" {
  value = var.enabled ? 5432 : null
}

output "database_name" {
  value = var.enabled ? var.database_name : null
}

output "server_name" {
  value = try(azurerm_postgresql_flexible_server.this[0].name, null)
}

output "credentials_secret_id" {
  description = "Azure Key Vault secret ID containing PostgreSQL credentials; it is not the password."
  value       = try(azurerm_key_vault_secret.credentials[0].id, null)
}

output "key_vault_id" {
  value = try(azurerm_key_vault.database[0].id, null)
}
