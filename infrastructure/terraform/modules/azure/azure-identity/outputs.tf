output "identity_ids" {
  value = { for name, identity in azurerm_user_assigned_identity.vm : name => identity.id }
}

output "principal_ids" {
  value = { for name, identity in azurerm_user_assigned_identity.vm : name => identity.principal_id }
}

output "client_ids" {
  value = { for name, identity in azurerm_user_assigned_identity.vm : name => identity.client_id }
}

output "application_key_vault_id" {
  value = try(azurerm_key_vault.application[0].id, null)
}

output "application_key_vault_name" {
  value = try(azurerm_key_vault.application[0].name, null)
}

output "application_key_vault_uri" {
  value = try(azurerm_key_vault.application[0].vault_uri, null)
}
