resource "aws_vpc" "this" {
  count = length(local.vms) > 0 ? 1 : 0

  cidr_block           = local.network.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "${local.resource_prefix}-vpc" })
}

resource "aws_subnet" "this" {
  for_each = length(local.vms) > 0 ? {
    management = local.network.management_subnet_cidr
    workload   = local.network.workload_subnet_cidr
  } : {}

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = each.value
  availability_zone = local.zone

  tags = merge(local.common_tags, { Name = "${local.resource_prefix}-${each.key}" })
}

resource "aws_subnet" "database" {
  for_each = local.database_subnets

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = each.value.cidr
  availability_zone = each.value.availability_zone

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-database-${each.key}"
    tier = "database"
  })

  lifecycle {
    precondition {
      condition     = length(var.database_subnet_cidrs) >= 2
      error_message = "Amazon RDS requires at least two private subnet CIDRs."
    }
  }
}

resource "aws_internet_gateway" "this" {
  count = length(local.vms) > 0 ? 1 : 0

  vpc_id = aws_vpc.this[0].id
  tags   = merge(local.common_tags, { Name = "${local.resource_prefix}-igw" })
}

resource "aws_route_table" "public" {
  count = length(local.vms) > 0 ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(local.common_tags, { Name = "${local.resource_prefix}-public" })
}

resource "aws_route_table_association" "this" {
  for_each = {
    for name, subnet in aws_subnet.this : name => subnet
    if name == "management" || !var.create_workload_nat_gateway
  }

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_eip" "nat" {
  count = var.create_workload_nat_gateway ? 1 : 0

  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.resource_prefix}-nat" })
}

resource "aws_nat_gateway" "this" {
  count = var.create_workload_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.this["management"].id
  tags          = merge(local.common_tags, { Name = "${local.resource_prefix}-nat" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "workload_private" {
  count = var.create_workload_nat_gateway ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[0].id
  }

  tags = merge(local.common_tags, { Name = "${local.resource_prefix}-workload-private" })
}

resource "aws_route_table_association" "workload_private" {
  count = var.create_workload_nat_gateway ? 1 : 0

  subnet_id      = aws_subnet.this["workload"].id
  route_table_id = aws_route_table.workload_private[0].id
}
