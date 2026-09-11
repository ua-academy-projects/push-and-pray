output "connection" {
  value = {
    host = google_sql_database_instance.this.private_ip_address
    port = 5432
    name = google_sql_database.this.name
    user = google_sql_user.this.name
  }
}
