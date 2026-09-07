resource "aws_internet_gateway" "main" {
  for_each = local.locations

  region = each.value.region
  vpc_id = aws_vpc.main[each.key].id
  tags   = merge(local.labels, { Name = "${local.resource_prefix}-igw${local.location_suffixes[each.key]}" })
}

resource "aws_eip" "nat" {
  for_each = local.locations

  region = each.value.region
  domain = "vpc"
  tags   = merge(local.labels, { Name = "${local.resource_prefix}-nat-ip${local.location_suffixes[each.key]}" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  for_each = local.locations

  region        = each.value.region
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.management[each.key].id
  tags          = merge(local.labels, { Name = "${local.resource_prefix}-nat${local.location_suffixes[each.key]}" })
}

resource "aws_route_table" "management" {
  for_each = local.locations

  region = each.value.region
  vpc_id = aws_vpc.main[each.key].id
  tags   = merge(local.labels, { Name = "${local.resource_prefix}-management${local.location_suffixes[each.key]}" })
}

resource "aws_route" "management_internet" {
  for_each = local.locations

  region                 = each.value.region
  route_table_id         = aws_route_table.management[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[each.key].id
}

resource "aws_route_table_association" "management" {
  for_each = local.locations

  region         = each.value.region
  subnet_id      = aws_subnet.management[each.key].id
  route_table_id = aws_route_table.management[each.key].id
}

resource "aws_route_table" "workload" {
  for_each = local.locations

  region = each.value.region
  vpc_id = aws_vpc.main[each.key].id
  tags   = merge(local.labels, { Name = "${local.resource_prefix}-workload${local.location_suffixes[each.key]}" })
}

resource "aws_route" "workload_internet" {
  for_each = local.locations

  region                 = each.value.region
  route_table_id         = aws_route_table.workload[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[each.key].id
}

resource "aws_route_table_association" "workload" {
  for_each = local.locations

  region         = each.value.region
  subnet_id      = aws_subnet.workload[each.key].id
  route_table_id = aws_route_table.workload[each.key].id
}
