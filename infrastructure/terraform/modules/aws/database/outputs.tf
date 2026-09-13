output "database" {
  description = "Non-secret RDS connection metadata and its managed admin-secret reference."
  value = local.enabled ? {
    provider            = "aws"
    host                = aws_db_instance.postgres[0].address
    port                = aws_db_instance.postgres[0].port
    name                = aws_db_instance.postgres[0].db_name
    admin_user          = aws_db_instance.postgres[0].username
    admin_secret_arn    = try(aws_db_instance.postgres[0].master_user_secret[0].secret_arn, null)
    instance_name       = aws_db_instance.postgres[0].identifier
    sslmode             = "require"
    publicly_accessible = false
  } : null
}

output "enabled" {
  description = "Whether this provider-specific managed database is selected."
  value       = local.enabled
}
