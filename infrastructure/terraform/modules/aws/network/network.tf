resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
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

# RDS DB subnet groups must span at least two Availability Zones. These subnets
# deliberately have no default route to the internet; the VPC-local route is
# enough for workload instances to reach the database.
resource "aws_subnet" "database" {
  for_each = {
    for subnet in var.database_subnets : subnet.availability_zone => subnet
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.availability_zone

  tags = {
    Name = "${var.resource_prefix}-database-${each.key}"
  }
}

resource "aws_subnet" "eks_private" {
  for_each = { for subnet in var.eks_private_subnets : subnet.availability_zone => subnet }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.availability_zone
  tags = {
    Name                              = "${var.resource_prefix}-eks-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "eks_public" {
  for_each = { for subnet in var.eks_public_subnets : subnet.availability_zone => subnet }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true
  tags = {
    Name                     = "${var.resource_prefix}-eks-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
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
