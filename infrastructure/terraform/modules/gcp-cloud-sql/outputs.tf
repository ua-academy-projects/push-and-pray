output "private_ip_address" {
  value = try(google_sql_database_instance.this[0].private_ip_address, null)
}

output "port" {
  value = var.enabled ? 5432 : null
}

output "database_name" {
  value = var.enabled ? var.database_name : null
}

output "instance_name" {
  value = try(google_sql_database_instance.this[0].name, null)
}

output "connection_name" {
  value = try(google_sql_database_instance.this[0].connection_name, null)
}

output "credentials_secret_id" {
  description = "Secret Manager ID containing Cloud SQL credentials; it is not the password."
  value       = try(google_secret_manager_secret.credentials[0].secret_id, null)
}
