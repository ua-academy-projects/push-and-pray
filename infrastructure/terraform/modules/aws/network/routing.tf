resource "aws_internet_gateway" "main" {
  count = local.enabled ? 1 : 0

  vpc_id = aws_vpc.main[0].id
}

resource "aws_route_table" "public" {
  count = local.enabled ? 1 : 0

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }
}

resource "aws_route_table" "private" {
  count = local.enabled ? 1 : 0

  vpc_id = aws_vpc.main[0].id
}

resource "aws_route_table_association" "public" {
  count = local.enabled ? 1 : 0

  route_table_id = aws_route_table.public[0].id
  subnet_id      = aws_subnet.workload[0].id
}

resource "aws_route_table_association" "eks_secondary" {
  count = local.eks_enabled ? 1 : 0

  route_table_id = aws_route_table.public[0].id
  subnet_id      = aws_subnet.eks_secondary[0].id
}


resource "aws_route_table_association" "rds_primary" {
  count = local.rds_enabled ? 1 : 0

  route_table_id = aws_route_table.private[0].id
  subnet_id      = aws_subnet.rds_primary[0].id
}

resource "aws_route_table_association" "rds_secondary" {
  count = local.rds_enabled ? 1 : 0

  route_table_id = aws_route_table.private[0].id
  subnet_id      = aws_subnet.rds_secondary[0].id
}
