output "management_subnet_id" {
  description = "ID of the AWS management subnet."
  value       = try(aws_subnet.management["this"].id, null)
}

output "workload_subnet_id" {
  description = "ID of the AWS workload subnet."
  value       = try(aws_subnet.workload["this"].id, null)
}

output "security_group_ids" {
  description = "AWS security group IDs keyed by logical role."
  value = {
    for role, security_group in aws_security_group.role :
    role => security_group.id
  }
}
