output "networks" {
  description = "AWS network identifiers keyed by logical location."
  value = {
    for location in keys(local.placements) : location => {
      region               = local.placements[location].region
      vpc_id               = aws_vpc.this[location].id
      management_subnet_id = aws_subnet.management[location].id
      workload_subnet_id   = aws_subnet.workload[location].id
    }
  }
}
