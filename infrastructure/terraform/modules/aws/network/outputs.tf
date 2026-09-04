output "management_subnet_id" { value = aws_subnet.management.id }
output "workload_subnet_id" { value = aws_subnet.workload.id }
output "public_subnet_id" { value = aws_subnet.public.id }
output "workload_route_table_id" { value = aws_route_table.workload.id }
output "security_group_ids" {
  value = { for role, group in aws_security_group.role : role => group.id }
}
