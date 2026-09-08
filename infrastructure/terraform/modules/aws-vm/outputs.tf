output "public_ips" {
  description = "Static public IP addresses keyed by logical VM name."
  value = {
    for name, address in aws_eip.public : name => address.public_ip
  }
}
