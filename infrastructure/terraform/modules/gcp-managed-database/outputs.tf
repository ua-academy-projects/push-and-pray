output "connection_name" {
  description = "Cloud SQL instance connection name used by the Auth Proxy."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip" {
  description = "Private Cloud SQL address."
  value       = google_sql_database_instance.this.private_ip_address
}
