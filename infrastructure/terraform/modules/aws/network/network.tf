resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = {
    Name = "VPC"
  }
}

resource "aws_subnet" "management" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.management_subnet_cidr
  availability_zone = var.availability_zone
  tags = {
    Name = "management_vpc"
  }
}

resource "aws_route_table_association" "management_association" {
  subnet_id      = aws_subnet.management.id
  route_table_id = aws_route_table.management.id
}

resource "aws_subnet" "workload" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.workload_subnet_cidr
  availability_zone = var.availability_zone
  tags = {
    Name = "wordload_vpc"
  }

}
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "internet gateway"
  }
}

resource "aws_eip" "ip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.ip.id
  subnet_id     = aws_subnet.management.id

  tags = {
    Name = "nat"
  }
  depends_on = [aws_internet_gateway.gw]
}
resource "aws_route_table_association" "workload_association" {
  subnet_id      = aws_subnet.workload.id
  route_table_id = aws_route_table.workload.id
}
