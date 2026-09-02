output "secret_resource_names" {
  description = "AWS Secrets Manager ARNs by secret ID."
  value = {
    for secret_id, secret in aws_secretsmanager_secret.this :
    secret_id => secret.arn
  }
}
