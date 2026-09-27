output "vpc_id" {
  value = try(aws_vpc.this[0].id, null)
}
output "subnet_ids" {
  value = { for name, subnet in aws_subnet.this : name => subnet.id }
}

output "database_subnet_ids" {
  description = "Private RDS subnet IDs in distinct Availability Zones."
  value       = [for subnet in aws_subnet.database : subnet.id]
}

output "nat_public_ip" {
  description = "Public IP of the optional workload NAT Gateway."
  value       = try(aws_eip.nat[0].public_ip, null)
}
