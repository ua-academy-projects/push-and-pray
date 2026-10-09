output "route_table_id" {
  description = "ID of the route table attached to the workload subnet."
  value       = azurerm_route_table.via_bastion.id
}
