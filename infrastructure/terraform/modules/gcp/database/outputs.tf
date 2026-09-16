output "connection" {
  value = {
    host = google_sql_database_instance.this.private_ip_address
    port = 5432
    name = var.database_name
    user = var.username
  }
}

output "instance_name" {
  value = google_sql_database_instance.this.name
}
