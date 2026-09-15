output "hostname" {
  description = "Private DNS hostname for PostgreSQL."
  value       = aws_route53_record.postgresql.fqdn
}

output "resource_id" {
  description = "RDS DB instance resource ID."
  value       = aws_db_instance.this.resource_id
}
