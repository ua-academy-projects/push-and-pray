output "name" {
  description = "Name of the AWS workload VM."
  value       = local.name
}

output "internal_ip" {
  description = "Private IP address of the AWS workload VM."
  value       = aws_instance.workload.private_ip
}

output "public_ip" {
  description = "Elastic IP address, or null when none is assigned."
  value       = local.vm.assign_public_ip ? aws_eip.public[0].public_ip : null
}

output "iam_role_name" {
  description = "Name of the workload IAM role."
  value       = aws_iam_role.workload.name
}

output "iam_role_arn" {
  description = "ARN of the workload IAM role."
  value       = aws_iam_role.workload.arn
}
