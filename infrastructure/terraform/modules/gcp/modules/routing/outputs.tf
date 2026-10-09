output "route_names" {
  description = "Route name by destination range."
  value       = { for cidr, route in google_compute_route.via_bastion : cidr => route.name }
}
