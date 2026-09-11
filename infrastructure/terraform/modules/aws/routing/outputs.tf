output "route_table_ids" {
  value = {
    public   = aws_route_table.public.id
    workload = aws_route_table.workload.id
  }
}
