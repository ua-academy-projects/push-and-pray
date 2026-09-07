output "secret_arns" {
  description = "AWS Secrets Manager ARNs by logical secret ID. Values are metadata only; no secret values are exposed."
  value = {
    for secret_id, secret in aws_secretsmanager_secret.this :
    secret_id => secret.arn
  }
}


