output "management_subnet_id" {
  description = "id submnet managment"
  value       = aws_subnet.management.id
}

output "workload_subnet_id" {
  description = "id submnet workload"
  value       = aws_subnet.workload.id
}

output "vpc_id" {
  value = aws_vpc.main.id

}
