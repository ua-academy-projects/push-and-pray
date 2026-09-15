output "secret_arns" {
    value       = { for secret_id, secret in aws_secretsmanager_secret.this : secret_id => secret.arn }
}