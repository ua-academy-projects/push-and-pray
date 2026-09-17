output "names" {
  description = "AWS key pair names keyed by logical location."
  value = {
    for location, key_pair in aws_key_pair.bootstrap : location => key_pair.key_name
  }
}
