output "host" {
  value = google_sql_database_instance.main.private_ip_address
}

output "port" {
  value = var.database.port
}

output "database_name" {
  value = google_sql_database.database.name
}

output "username" {
  value = google_sql_user.database_user.name
}
