output "name" {
  description = "Name of the workload VM."
  value       = aws_instance.workload.tags["Name"]
}

output "internal_ip" {
  description = "Internal IP address of the workload VM."
  value       = aws_instance.workload.private_ip
}

output "public_ip" {
  description = "Static public IP address, or null when none is assigned."
  value       = var.assign_public_ip ? aws_eip.public[0].public_ip : null
}

output "network_groups" {
  description = "Effective network group identifiers attached to the VM. Security group IDs in this module."
  value       = aws_instance.workload.vpc_security_group_ids
}

output "runtime_identity" {
  description = "Identity the VM runs as. The IAM role name in this module; the service-account email in the GCP module."
  value       = aws_iam_role.workload.name
}

output "runtime_identity_arn" {
  description = "ARN of the IAM role the VM runs as, for attaching secret policies."
  value       = aws_iam_role.workload.arn
}
