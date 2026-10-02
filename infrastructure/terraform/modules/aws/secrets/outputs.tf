output "secret_ids" {
  description = "AWS secret container IDs created from the project configuration."
  value       = keys(aws_secretsmanager_secret.this)
}

output "secret_resource_names" {
  description = "Fully qualified AWS secret ARNs by secret ID."
  value = {
    for secret_id, secret in aws_secretsmanager_secret.this : secret_id => secret.arn
  }
}
