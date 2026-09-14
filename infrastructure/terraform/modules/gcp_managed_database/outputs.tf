output "host" {
  description = "Private Cloud SQL address."
  value       = google_sql_database_instance.this.private_ip_address
}

output "port" {
  value = 5432
}

output "instance_name" {
  value = google_sql_database_instance.this.name
}

output "public_ipv4_enabled" {
  value = google_sql_database_instance.this.settings[0].ip_configuration[0].ipv4_enabled
}

output "private_network" {
  value = google_sql_database_instance.this.settings[0].ip_configuration[0].private_network
}

output "cron_database_name" {
  value = one([
    for flag in google_sql_database_instance.this.settings[0].database_flags : flag.value
    if flag.name == "cron.database_name"
  ])
}
