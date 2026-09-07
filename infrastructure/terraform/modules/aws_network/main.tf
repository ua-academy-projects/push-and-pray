resource "aws_vpc" "main" {
  cidr_block           = var.config.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-vpc"
    },
  )
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-igw"
    },
  )
}

resource "aws_subnet" "management" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.config.management_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-management"
      Type = "public"
    },
  )
}

resource "aws_subnet" "workload" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.config.workload_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-workload"
      Type = "private"
    },
  )
}

resource "aws_eip" "nat" {
  count  = var.config.aws_enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-nat-ip"
    },
  )
}

resource "aws_nat_gateway" "main" {
  count = var.config.aws_enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.management.id

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-nat"
    },
  )

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "management" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-management"
    },
  )
}

resource "aws_route_table_association" "management" {
  subnet_id      = aws_subnet.management.id
  route_table_id = aws_route_table.management.id
}

resource "aws_route_table" "workload" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.config.aws_enable_nat_gateway ? [1] : []

    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-workload"
    },
  )
}

resource "aws_route_table_association" "workload" {
  subnet_id      = aws_subnet.workload.id
  route_table_id = aws_route_table.workload.id
}
