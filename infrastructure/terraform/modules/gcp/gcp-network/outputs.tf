output "network_id" {
  value = try(google_compute_network.main[0].id, null)
}
output "subnet_ids" {
  value = { for name, subnet in google_compute_subnetwork.this : name => subnet.id }
}
