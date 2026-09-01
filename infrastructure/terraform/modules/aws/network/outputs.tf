output "management_subnet_id" {
  description = "ID of the subnet used by the bastion."
  value       = aws_subnet.management.id
}

output "workload_subnet_id" {
  description = "ID of the subnet used by workload VMs."
  value       = aws_subnet.workload.id
}

output "workload_groups" {
  description = "Network group identifiers keyed by logical name. Security group IDs in this module; Compute Engine network tags in the GCP module."
  value = merge(local.workload_groups, {
    bastion = aws_security_group.bastion.id
  })
}
