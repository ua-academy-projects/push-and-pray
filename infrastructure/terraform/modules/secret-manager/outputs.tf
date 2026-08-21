output "secret_ids" {
  description = "Managed Secret Manager secret IDs."
  value       = toset([for secret in google_secret_manager_secret.managed : secret.secret_id])
}