resource "aws_vpc" "this" {
  for_each = local.placements

  region               = each.value.region
  cidr_block           = var.config.network.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.context.labels, { Name = "${local.context.resource_prefix}-${each.key}-vpc" })
}

resource "aws_subnet" "public" {
  for_each = local.placements

  region                  = each.value.region
  vpc_id                  = aws_vpc.this[each.key].id
  cidr_block              = var.config.network.public_subnet_cidr
  availability_zone       = each.value.zone
  map_public_ip_on_launch = false

  tags = merge(local.context.labels, { Name = "${local.context.resource_prefix}-${each.key}-public" })
}

resource "aws_subnet" "private" {
  for_each = local.placements

  region                  = each.value.region
  vpc_id                  = aws_vpc.this[each.key].id
  cidr_block              = var.config.network.private_subnet_cidr
  availability_zone       = each.value.zone
  map_public_ip_on_launch = false

  tags = merge(local.context.labels, { Name = "${local.context.resource_prefix}-${each.key}-private" })
}

resource "aws_internet_gateway" "this" {
  for_each = local.placements

  region = each.value.region
  vpc_id = aws_vpc.this[each.key].id
  tags   = merge(local.context.labels, { Name = "${local.context.resource_prefix}-${each.key}-igw" })
}

resource "aws_eip" "nat" {
  for_each = local.placements

  region = each.value.region
  domain = "vpc"
  tags   = merge(local.context.labels, { Name = "${local.context.resource_prefix}-${each.key}-nat-ip" })
}

resource "aws_nat_gateway" "this" {
  for_each = local.placements

  region        = each.value.region
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = merge(local.context.labels, { Name = "${local.context.resource_prefix}-${each.key}-nat" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  for_each = local.placements

  region = each.value.region
  vpc_id = aws_vpc.this[each.key].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[each.key].id
  }

  tags = merge(local.context.labels, { Name = "${local.context.resource_prefix}-${each.key}-public" })
}

resource "aws_route_table" "private" {
  for_each = local.placements

  region = each.value.region
  vpc_id = aws_vpc.this[each.key].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[each.key].id
  }

  tags = merge(local.context.labels, { Name = "${local.context.resource_prefix}-${each.key}-private" })
}

resource "aws_route_table_association" "public" {
  for_each = local.placements

  region         = each.value.region
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = local.placements

  region         = each.value.region
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}
