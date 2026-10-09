output "networks" {
  description = "AWS network identifiers keyed by logical location."
  value = {
    for location in keys(local.placements) : location => {
      region                 = local.placements[location].region
      vpc_id                 = try(aws_vpc.this[location].id, null)
      public_subnet_id       = try(aws_subnet.public[location].id, null)
      private_subnet_id      = try(aws_subnet.private[location].id, null)
      private_route_table_id = try(aws_route_table.private[location].id, null)
      database_subnet_ids = [
        for key, subnet in aws_subnet.database : subnet.id
        if startswith(key, "${location}/")
      ]
    }
  }
}
