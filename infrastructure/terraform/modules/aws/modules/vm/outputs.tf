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

output "instance_id" {
  description = "ID of the instance."
  value       = aws_instance.workload.id
}

output "instance_arn" {
  description = "ARN of the instance."
  value       = aws_instance.workload.arn
}

output "availability_zone" {
  description = "Zone the instance runs in. Inherited from its subnet, not from an input."
  value       = aws_instance.workload.availability_zone
}

output "private_dns" {
  description = "Internal DNS name AWS assigned to the instance."
  value       = aws_instance.workload.private_dns
}

output "instance_type" {
  description = "Instance type the size label resolved to."
  value       = local.instance_type
}

output "boot_disk" {
  description = "What the boot disk labels resolved to, alongside its size."
  value = {
    image   = local.ami
    type    = local.boot_disk_type
    size_gb = var.vm.boot_disk.size_gb
  }
}

output "root_volume_id" {
  description = "ID of the encrypted root volume."
  value       = aws_instance.workload.root_block_device[0].volume_id
}

output "role" {
  description = "Functional role of this VM, echoed back for callers indexing by role."
  value       = var.vm.role
}

output "identity_member" {
  description = "The IAM role ARN, named to match the GCP module's IAM member string."
  value       = aws_iam_role.workload.arn
}

output "iam_role_unique_id" {
  description = "Stable unique ID of the IAM role, which survives a rename."
  value       = aws_iam_role.workload.unique_id
}

output "iam_instance_profile_name" {
  description = "Name of the instance profile carrying the role onto the instance."
  value       = aws_iam_instance_profile.workload.name
}

output "iam_instance_profile_arn" {
  description = "ARN of the instance profile."
  value       = aws_iam_instance_profile.workload.arn
}

output "public_address_allocation_id" {
  description = "Allocation ID of the Elastic IP, or null when none is assigned."
  value       = one(aws_eip.public[*].allocation_id)
}
