output "security_group_ids" {
  description = "id submnet workload"
  value = {

    bastion  = aws_security_group.bastion_ssh.id,
    database = aws_security_group.infra.id,
    history  = aws_security_group.history.id,
    fetcher  = aws_security_group.fetcher.id,
    ui       = aws_security_group.ui.id,
  }
}

output "managed_database_security_group_id" {
  description = "Security group ID for private RDS PostgreSQL, or null outside managed database mode."
  value       = try(aws_security_group.managed_database[0].id, null)
}
