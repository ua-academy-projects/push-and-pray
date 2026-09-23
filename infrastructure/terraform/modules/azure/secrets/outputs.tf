output "key_vault_id" {
  value = try(azurerm_key_vault.this[0].id, null)
}

output "key_vault_name" {
  value = try(azurerm_key_vault.this[0].name, null)
}