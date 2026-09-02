output "vpc_id" {
  description = "AWS VPC ID."
  value       = aws_vpc.main.id
}

output "management_subnet_id" {
  description = "Public subnet used by internet-facing workloads."
  value       = aws_subnet.management.id
}

output "workload_subnet_id" {
  description = "Private subnet used by internal workloads."
  value       = aws_subnet.workload.id
}

output "security_group_ids" {
  description = "Security groups indexed by workload role."

  value = {
    bastion  = aws_security_group.bastion.id
    database = aws_security_group.database.id
    history  = aws_security_group.history.id
    fetcher  = aws_security_group.fetcher.id
    ui       = aws_security_group.ui.id
  }
}