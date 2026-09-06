output "name" {
  description = "Name of the workload instance."
  value       = aws_instance.workload.tags["Name"]
}

output "internal_ip" {
  description = "Private IP address of the workload instance."
  value       = aws_instance.workload.private_ip
}

output "public_ip" {
  description = "Static Elastic IP address, or null when none is assigned."
  value       = var.vm.assign_public_ip ? aws_eip.public[0].public_ip : null
}

output "security_group_ids" {
  description = "Security groups the workload instance belongs to."
  value       = aws_instance.workload.vpc_security_group_ids
}

output "identity" {
  description = "ARN of the workload instance's dedicated IAM role."
  value       = aws_iam_role.workload.arn
}

output "iam_role_name" {
  description = "Name of the workload instance's IAM role, for attaching inline policies."
  value       = aws_iam_role.workload.name
}
