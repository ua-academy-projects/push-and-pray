output "networks" {
  description = "AWS network identifiers keyed by logical location."
  value = {
    for location in keys(local.placements) : location => {
      region            = local.placements[location].region
      vpc_id            = aws_vpc.this[location].id
      public_subnet_id  = aws_subnet.public[location].id
      private_subnet_id = aws_subnet.private[location].id
      database_subnet_ids = [
        for key, subnet in aws_subnet.database : subnet.id
        if startswith(key, "${location}/")
      ]
    }
  }
}
