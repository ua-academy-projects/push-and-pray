resource "aws_internet_gateway" "main" {
  count = local.enabled ? 1 : 0

  vpc_id = aws_vpc.main[0].id
}

resource "aws_eip" "nat_ip" {
  count = local.enabled ? 1 : 0

  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  count = local.enabled ? 1 : 0

  allocation_id = aws_eip.nat_ip[0].id
  subnet_id     = aws_subnet.management[0].id

  depends_on = [aws_internet_gateway.main]
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

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }
}

resource "aws_route_table_association" "public" {
  count = local.enabled ? 1 : 0

  route_table_id = aws_route_table.public[0].id
  subnet_id      = aws_subnet.management[0].id
}

resource "aws_route_table_association" "private" {
  count = local.enabled ? 1 : 0

  route_table_id = aws_route_table.private[0].id
  subnet_id      = aws_subnet.workload[0].id
}
