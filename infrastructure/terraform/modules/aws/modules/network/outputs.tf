output "public_subnet_id" {
  description = "ID of the subnet used by VMs that hold a public IP."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the subnet used by VMs that reach the internet through NAT."
  value       = aws_subnet.private.id
}

output "security_group_ids" {
  description = "Security group ID by scope. The AWS counterpart of the GCP network tags."
  value       = { for scope, group in aws_security_group.scope : scope => group.id }
}
