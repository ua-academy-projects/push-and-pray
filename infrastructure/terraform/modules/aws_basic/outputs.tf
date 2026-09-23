output "instance_profile_names" {
  description = "EC2 instance profile names keyed by VM name."
  value = {
    for name, profile in aws_iam_instance_profile.profiles :
    name => profile.name
  }

  depends_on = [aws_iam_role_policy.readers]
}

output "secret_arns" {
  description = "Secrets Manager ARNs keyed by configured secret ID."
  value = {
    for secret_id, secret in aws_secretsmanager_secret.secrets :
    secret_id => secret.arn
  }
}
