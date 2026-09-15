output "public_subnet_id" {
  description = "ID of the subnet used by VMs that hold a public IP."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the subnet used by VMs that reach the internet through NAT."
  value       = aws_subnet.private.id
}

output "database_subnet_ids" {
  description = "IDs of the subnets reserved for the managed database, in the order their ranges were configured. Empty when no such subnets exist."
  value       = aws_subnet.database[*].id
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_arn" {
  description = "ARN of the VPC."
  value       = aws_vpc.main.arn
}

output "vpc_cidr_block" {
  description = "Range of the VPC. Every subnet falls inside it."
  value       = aws_vpc.main.cidr_block
}

output "availability_zone" {
  description = "Zone both subnets are bound to. An AWS subnet cannot span zones."
  value       = aws_subnet.public.availability_zone
}

output "public_subnet_cidr" {
  description = "Range of the subnet routed to the internet gateway."
  value       = aws_subnet.public.cidr_block
}

output "private_subnet_cidr" {
  description = "Range of the subnet routed through NAT."
  value       = aws_subnet.private.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway, or null when no VM needs one."
  value       = one(aws_nat_gateway.main[*].id)
}

output "nat_public_ip" {
  description = "Address every private VM appears to come from, or null when no NAT gateway exists. Useful for allowlisting this deployment upstream."
  value       = one(aws_eip.nat[*].public_ip)
}

output "public_route_table_id" {
  description = "ID of the route table attached to the public subnet."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the route table attached to the private subnet."
  value       = aws_route_table.private.id
}
