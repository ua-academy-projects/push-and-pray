output "management_subnet_id" {
  description = "id submnet managment"
  value       = aws_subnet.management.id
}

output "workload_subnet_id" {
  description = "id submnet workload"
  value       = aws_subnet.workload.id
}

output "database_subnet_ids" {
  description = "Private subnet IDs for the RDS DB subnet group, keyed by Availability Zone."
  value = {
    for availability_zone, subnet in aws_subnet.database : availability_zone => subnet.id
  }
}

output "vpc_id" {
  value = aws_vpc.main.id

}
