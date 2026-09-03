output "names" {
  description = "Name of the EC2 workload instance."
  value       = local.vm_names
}

output "private_ips" {
  description = "Private IPv4 address of the EC2 workload instance."
  value = {
    for name, instance in aws_instance.workload :
    name => instance.private_ip
  }
}

output "public_ips" {
  description = "Public IPv4 address of the EC2 workload instance, or null when none is assigned."
  value = {
    for name, instance in aws_instance.workload :
    name => instance.public_ip
  }
}
