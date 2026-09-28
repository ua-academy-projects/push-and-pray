output "public_ips" {
  description = "Static public IP addresses keyed by logical VM name."
  value = {
    for name, address in google_compute_address.public : name => address.address
  }
}

output "instance_ids" {
  description = "Compute Engine instance IDs keyed by logical VM name."
  value = {
    for name, instance in google_compute_instance.this : name => instance.instance_id
  }
}

output "instance_self_links" {
  description = "Compute Engine instance self-links keyed by logical VM name."
  value = {
    for name, instance in google_compute_instance.this : name => instance.self_link
  }
}
