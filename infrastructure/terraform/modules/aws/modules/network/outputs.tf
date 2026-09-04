output "vpc_id" {
  value = aws_vpc.main.id
}

output "management_subnet_id" {
  value = aws_subnet.management.id
}

output "workload_subnet_id" {
  value = aws_subnet.workload.id
}

output "security_group_ids_by_role" {
  value = {
    for role, security_group in aws_security_group.role :
    role => security_group.id
  }
}