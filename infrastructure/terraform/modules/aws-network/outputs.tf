output "management_subnet_id" {
  description = "ID of the AWS management subnet."
  value       = aws_subnet.management.id
}

output "workload_subnet_id" {
  description = "ID of the AWS workload subnet."
  value       = aws_subnet.workload.id
}

output "security_group_ids" {
  description = "AWS security group IDs keyed by logical role."
  value = {
    for role, security_group in aws_security_group.role :
    role => security_group.id
  }
}
