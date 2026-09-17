output "connection" {
  description = "RDS connection metadata for deployment tooling; null when disabled. No password values."
  value = local.enabled ? {
    host             = aws_db_instance.this[0].address
    port             = aws_db_instance.this[0].port
    database         = aws_db_instance.this[0].db_name
    admin_username   = aws_db_instance.this[0].username
    admin_secret_arn = aws_db_instance.this[0].master_user_secret[0].secret_arn
    sslmode          = "verify-full"
    ca_bundle_url    = "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"
  } : null
}

output "monitoring" {
  value = local.enabled ? {
    id = aws_db_instance.this[0].identifier
  } : null
}
