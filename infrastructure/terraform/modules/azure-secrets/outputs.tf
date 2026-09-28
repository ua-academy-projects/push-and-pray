output "identity_ids" {
  description = "User-assigned managed identity IDs keyed by logical Azure VM name."
  value = {
    for name, identity in azurerm_user_assigned_identity.vm : name => identity.id
  }
}

output "key_vault" {
  description = "Non-secret Azure Key Vault connection metadata."
  value = try({
    id   = azurerm_key_vault.this["main"].id
    name = azurerm_key_vault.this["main"].name
    uri  = azurerm_key_vault.this["main"].vault_uri
  }, null)
}
