output "secret_resource_names" {
  description = "AWS Secrets Manager ARNs by secret ID."
  value = {
    for secret_id, secret in aws_secretsmanager_secret.this :
    secret_id => secret.arn
  }
}

output "secret_ids" {
  description = "Secret IDs selected for AWS workloads."
  value       = local.all_secret_ids
}
