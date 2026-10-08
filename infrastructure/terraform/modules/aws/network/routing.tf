resource "aws_route_table" "management" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "routing table for internet gateway"
  }
}

resource "aws_route_table" "workload" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "routing table for nat  gateway"
  }
}

# Keep every workload-table route as a standalone resource. Mixing inline
# `route` blocks with aws_route makes the route-table resource delete routes
# that aws_route is meant to manage.
resource "aws_route" "workload_internet" {
  route_table_id         = aws_route_table.workload.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "eks_private" {
  for_each       = aws_subnet.eks_private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.workload.id
}

resource "aws_route_table_association" "eks_public" {
  for_each       = aws_subnet.eks_public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.management.id
}
