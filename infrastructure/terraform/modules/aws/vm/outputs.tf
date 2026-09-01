output "name" {
  description = "Name of the EC2 workload instance."
  value       = var.name
}

output "private_ip" {
  description = "Private IPv4 address of the EC2 workload instance."
  value       = aws_instance.workload.private_ip
}

output "public_ip" {
  description = "Public IPv4 address of the EC2 workload instance, or null when none is assigned."
  value       = var.assign_public_ip ? aws_instance.workload.public_ip : null
}
