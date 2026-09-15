output "host" {
  description = "Private DNS name the workloads connect to. Resolves inside the VPC only."
  value       = aws_db_instance.main.address
}

output "port" {
  description = "Port PostgreSQL listens on."
  value       = aws_db_instance.main.port
}

output "name" {
  description = "Name of the application database."
  value       = aws_db_instance.main.db_name
}

output "instance_identifier" {
  description = "RDS instance identifier, for the API and the CLI."
  value       = aws_db_instance.main.identifier
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret RDS keeps the master password in. The name only - the value stays in Secrets Manager."
  value       = one(aws_db_instance.main.master_user_secret[*].secret_arn)
}

output "security_group_id" {
  description = "ID of the database's own security group."
  value       = aws_security_group.database.id
}
