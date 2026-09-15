output "host" {
  description = "Private address the workloads connect to: the Private Service Connect endpoint in the database subnet."
  value       = google_compute_address.endpoint.address
}

output "port" {
  description = "Port PostgreSQL listens on. Cloud SQL does not let it change."
  value       = 5432
}

output "name" {
  description = "Name of the application database."
  value       = google_sql_database.application.name
}

output "instance_name" {
  description = "Name of the Cloud SQL instance, for the Admin API and gcloud."
  value       = google_sql_database_instance.main.name
}

output "connection_name" {
  description = "project:region:instance, the form the Cloud SQL tooling addresses an instance by."
  value       = google_sql_database_instance.main.connection_name
}

output "endpoint_name" {
  description = "Name of the endpoint address. The Ansible inventory looks the host up by it."
  value       = google_compute_address.endpoint.name
}
