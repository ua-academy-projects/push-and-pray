output "key_name" {
  description = "Name of the bootstrap EC2 key pair."
  value       = aws_key_pair.bootstrap.key_name
}
