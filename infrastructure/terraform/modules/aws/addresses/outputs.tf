output "allocation_ids" {
    description = "EIP allocation IDs for VMs with assign_public_ip = true, by VM key."
    value       = { for name, eip in aws_eip.public : name => eip.id }
}

output "public_ips" {
    description = "EIP public IP addresses for VMs with assign_public_ip = true, by VM key."
    value       = { for name, eip in aws_eip.public : name => eip.public_ip }
}
