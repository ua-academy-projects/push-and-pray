output "host" {
  description = "Private RDS endpoint hostname."
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "instance_id" {
  value = aws_db_instance.this.id
}

output "publicly_accessible" {
  value = aws_db_instance.this.publicly_accessible
}

output "database_subnet_count" {
  value = length(aws_subnet.database)
}

output "database_subnet_availability_zones" {
  value = aws_subnet.database[*].availability_zone
}

output "database_subnet_cidrs" {
  value = aws_subnet.database[*].cidr_block
}

output "private_route_association_count" {
  value = length(aws_route_table_association.database)
}

output "cron_database_name" {
  value = one([
    for parameter in aws_db_parameter_group.this.parameter : parameter.value
    if parameter.name == "cron.database_name"
  ])
}

output "ingress_rule_count" {
  value = length(aws_vpc_security_group_ingress_rule.postgresql)
}
