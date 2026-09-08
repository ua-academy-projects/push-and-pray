output "public_ips" {
  description = "Static public IP addresses keyed by logical VM name."
  value = {
    for name, address in google_compute_address.public : name => address.address
  }
}
