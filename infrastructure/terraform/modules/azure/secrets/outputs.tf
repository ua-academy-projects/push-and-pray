output "vault_id" {
  value = azurerm_key_vault.main.id
}

output "vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "secret_resource_ids" {
  value = merge(
    { for name, secret in azurerm_key_vault_secret.external : name => secret.id },
    { for name, secret in azurerm_key_vault_secret.managed : name => secret.id },
  )
}
