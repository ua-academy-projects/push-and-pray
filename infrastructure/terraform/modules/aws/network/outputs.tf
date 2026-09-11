output "vpc_id" { value = aws_vpc.this.id }
output "management_subnet_id" { value = aws_subnet.management.id }
output "workload_subnet_id" { value = aws_subnet.workload.id }
output "public_subnet_id" { value = aws_subnet.public.id }
