output "resource_group_name" {
  description = "Azure resource group name reserved for this environment."
  value       = "${var.config.name_prefix}-${var.config.environment}"
}

output "key_vault_uri" {
  description = "Azure Key Vault data-plane URI; populated when azure_basic is implemented."
  value       = null
}
