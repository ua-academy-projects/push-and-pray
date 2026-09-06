output "name" {
  description = "Name of the workload VM."
  value       = var.name
}

output "internal_ip" {
  description = "Internal IP address of the workload VM."
  value       = aws_instance.workload.private_ip
}

output "public_ip" {
  description = "Static external IP address, or null when none is assigned."
  value       = var.assign_public_ip ? aws_eip.public[0].public_ip : null
}

output "role_arn" {
  description = "ARN of the workload VM's dedicated IAM role."
  value       = aws_iam_role.ec2_role.arn
}

output "role_name" {
  description = "Name of the workload VM's dedicated IAM role. Needed to attach IAM policies to the role (aws_iam_role_policy takes a role name, not an ARN)."
  value       = aws_iam_role.ec2_role.name
}
