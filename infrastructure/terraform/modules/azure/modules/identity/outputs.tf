output "identity" {
  description = "Resource ID of the identity. The Azure equivalent of the GCP service-account email and the AWS role ARN."
  value       = azurerm_user_assigned_identity.workload.id
}

output "id" {
  description = "Resource ID of the identity, which is what a VM and the metadata service take."
  value       = azurerm_user_assigned_identity.workload.id
}

output "principal_id" {
  description = "Object ID of the identity's service principal, which is what a role assignment takes."
  value       = azurerm_user_assigned_identity.workload.principal_id
}

output "client_id" {
  description = "Client ID of the identity."
  value       = azurerm_user_assigned_identity.workload.client_id
}

output "name" {
  description = "Name of the identity."
  value       = azurerm_user_assigned_identity.workload.name
}
