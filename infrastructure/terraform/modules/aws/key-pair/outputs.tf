output "key_name" {
  description = "Name of the bootstrap EC2 key pair, or null when AWS has no VMs."
  value       = try(aws_key_pair.bootstrap["this"].key_name, null)
}
