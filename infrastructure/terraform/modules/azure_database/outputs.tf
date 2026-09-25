output "connection" {
  description = "Non-secret Azure PostgreSQL connection data."
  value = {
    host      = null
    port      = var.config.services.database.port
    name      = var.config.services.database.name
    username  = var.config.services.database.username
    ssl_mode  = var.config.services.database.ssl_mode
    server_id = null
  }
}
