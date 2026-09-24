output "secret_ids" {
  description = "Azure secret IDs the project configuration maps to workloads."
  value       = local.all_secret_ids
}

output "secret_resource_names" {
  description = "Versionless Key Vault secret URIs by secret ID. This is the data-plane address a workload reads, not the ARM scope a grant is written against."
  value = {
    for secret_id in local.all_secret_ids :
    secret_id => "${azurerm_key_vault.main[0].vault_uri}secrets/${secret_id}"
  }
}

output "vault" {
  description = "The vault the database module writes the administrator credential into; null when no Azure feature needs one."
  value = local.enabled ? {
    id        = azurerm_key_vault.main[0].id
    name      = azurerm_key_vault.main[0].name
    uri       = azurerm_key_vault.main[0].vault_uri
    tenant_id = azurerm_key_vault.main[0].tenant_id
  } : null
  depends_on = [azurerm_role_assignment.deployer]
}
