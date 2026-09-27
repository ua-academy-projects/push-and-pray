output "secret_arns" {
  description = "AWS Secrets Manager ARNs keyed by project secret ID."
  value       = { for id, secret in aws_secretsmanager_secret.this : id => secret.arn }
}

output "secret_names" {
  description = "AWS Secrets Manager names keyed by project secret ID."
  value       = { for id, secret in aws_secretsmanager_secret.this : id => secret.name }
}
