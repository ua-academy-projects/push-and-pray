output "security_group_ids" {
  value = { for role, group in aws_security_group.role : role => group.id }
}
