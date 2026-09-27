output "address" {
  description = "RDS DNS address."
  value       = try(aws_db_instance.this[0].address, null)
}

output "endpoint" {
  description = "RDS endpoint including the port."
  value       = try(aws_db_instance.this[0].endpoint, null)
}

output "port" {
  value = try(aws_db_instance.this[0].port, null)
}

output "database_name" {
  value = var.enabled ? var.database_name : null
}

output "identifier" {
  value = try(aws_db_instance.this[0].identifier, null)
}

output "arn" {
  value = try(aws_db_instance.this[0].arn, null)
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed master credential secret; it is not the password."
  value       = try(aws_db_instance.this[0].master_user_secret[0].secret_arn, null)
}
