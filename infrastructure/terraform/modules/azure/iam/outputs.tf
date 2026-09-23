output "identity_ids" {
  value = { for name, id in azurerm_user_assigned_identity.workload : name => id.id }
}

output "principal_ids" {
  value = { for name, id in azurerm_user_assigned_identity.workload : name => id.principal_id }
}