output "host" {
  description = "Address of the private endpoint the workloads connect to. Reachable inside the virtual network only."
  value       = azurerm_private_endpoint.main.private_service_connection[0].private_ip_address
}

output "port" {
  description = "Port PostgreSQL listens on."
  value       = var.port
}

output "name" {
  description = "Name of the application database."
  value       = azurerm_postgresql_flexible_server_database.application.name
}

output "server_name" {
  description = "Name of the flexible server, for the API and the CLI."
  value       = azurerm_postgresql_flexible_server.main.name
}

output "fqdn" {
  description = "The server's public name. It resolves to nothing reachable, public access being off; the endpoint address is what connects."
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "endpoint_name" {
  description = "Name of the private endpoint, which the Ansible inventory looks up."
  value       = azurerm_private_endpoint.main.name
}
