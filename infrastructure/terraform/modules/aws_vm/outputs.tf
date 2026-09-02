output "name" {
  description = "Name of the EC2 instance."
  value       = aws_instance.workload.tags["Name"]
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.workload.id
}

output "internal_ip" {
  description = "Private IP address of the EC2 instance."
  value       = aws_instance.workload.private_ip
}

output "public_ip" {
  description = "Elastic IP address, or null when the VM is private."
  value       = var.assign_public_ip ? aws_eip.public[0].public_ip : null
}

output "role" {
  description = "Functional role of the EC2 instance."
  value       = var.role
}

output "tags" {
  description = "Tags attached to the EC2 instance."
  value       = aws_instance.workload.tags
}

output "iam_role_name" {
  description = "IAM role attached to the EC2 instance."
  value       = aws_iam_role.workload.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the EC2 instance."
  value       = aws_iam_role.workload.arn
}