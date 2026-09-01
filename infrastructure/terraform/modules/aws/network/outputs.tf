output "management_subnet_id" {
  description = "id submnet managment"
  value       = aws_subnet.management.id
}

output "workload_subnet_id" {
  description = "id submnet workload"
  value       = aws_subnet.workload.id
}

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
