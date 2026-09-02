output "key_names_by_location" {
  description = "EC2 key-pair names keyed by abstract location."
  value       = { for location, key_pair in aws_key_pair.bootstrap : location => key_pair.key_name }
}
