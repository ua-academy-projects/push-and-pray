resource "aws_route_table" "management" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-management"
  })
}

resource "aws_route" "management_internet" {
  route_table_id         = aws_route_table.management.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "management" {
  subnet_id      = aws_subnet.management.id
  route_table_id = aws_route_table.management.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-nat"
  })

}

resource "aws_nat_gateway" "main" {
  allocation_id     = aws_eip.nat.id
  subnet_id         = aws_subnet.management.id
  connectivity_type = "public"
  # Keep automatic NAT allocation from taking a configured VM address.
  private_ip = cidrhost(var.config.network.management_subnet_cidr, -2)

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "vm" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-vm"
  })
}

resource "aws_route" "vm_internet" {
  route_table_id         = aws_route_table.vm.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "vm" {
  subnet_id      = aws_subnet.vm.id
  route_table_id = aws_route_table.vm.id
}
