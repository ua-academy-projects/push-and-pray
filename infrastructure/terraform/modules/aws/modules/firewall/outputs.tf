output "security_group_ids" {
  description = "Security group ID by scope. The AWS counterpart of the GCP network tags: an instance joins the group matching its role."
  value       = { for scope, group in aws_security_group.scope : scope => group.id }
}

output "security_group_names" {
  description = "Security group name by scope."
  value       = { for scope, group in aws_security_group.scope : scope => group.name }
}

output "security_group_arns" {
  description = "Security group ARN by scope."
  value       = { for scope, group in aws_security_group.scope : scope => group.arn }
}

output "scopes" {
  description = "The role scopes this contract is written in terms of."
  value       = sort(local.scopes)
}
