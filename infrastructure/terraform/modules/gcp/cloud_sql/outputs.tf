output "private_ip" {
    value = try(google_sql_database_instance.main[0].private_ip_address, null)
}
