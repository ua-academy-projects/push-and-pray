output "application_security_group_ids" {
  description = "Application security group ID by scope. The Azure counterpart of the GCP network tags and the AWS security groups: a network interface joins the group of its role, and a node with a public address also joins ingress."
  value       = { for scope, group in azurerm_application_security_group.scope : scope => group.id }
}

output "network_security_group_id" {
  description = "ID of the security group every subnet is attached to."
  value       = azurerm_network_security_group.main.id
}

output "network_security_group_name" {
  description = "Name of that security group, for modules that add rules of their own to it."
  value       = azurerm_network_security_group.main.name
}

output "scopes" {
  description = "The scopes this contract is written in terms of."
  value       = sort(local.scopes)
}
