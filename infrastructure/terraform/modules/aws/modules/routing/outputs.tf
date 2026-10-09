output "route_ids" {
  description = "Route ID by <route table>/<destination>."
  value       = { for key, route in aws_route.via_bastion : key => route.id }
}
