resource "aws_vpc" "main" {
  for_each = local.locations

  region               = each.value.region
  cidr_block           = var.config.network.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.labels, { Name = "${local.resource_prefix}-vpc${local.location_suffixes[each.key]}" })
}

resource "aws_subnet" "management" {
  for_each = local.locations

  region                  = each.value.region
  vpc_id                  = aws_vpc.main[each.key].id
  cidr_block              = var.config.network.management_subnet_cidr
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.labels, { Name = "${local.resource_prefix}-management${local.location_suffixes[each.key]}" })
}

resource "aws_subnet" "workload" {
  for_each = local.locations

  region                  = each.value.region
  vpc_id                  = aws_vpc.main[each.key].id
  cidr_block              = var.config.network.workload_subnet_cidr
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.labels, { Name = "${local.resource_prefix}-workload${local.location_suffixes[each.key]}" })
}
