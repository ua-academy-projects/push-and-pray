resource "aws_vpc" "main" {
  for_each = local.locations

  region               = each.value.region
  cidr_block           = var.config.network.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.labels, { Name = "${local.resource_prefix}-vpc${local.location_suffixes[each.key]}" })
}

resource "aws_internet_gateway" "main" {
  for_each = local.locations

  region = each.value.region
  vpc_id = aws_vpc.main[each.key].id
  tags   = merge(local.labels, { Name = "${local.resource_prefix}-igw${local.location_suffixes[each.key]}" })
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

resource "aws_security_group" "role" {
  for_each = local.role_instances

  region      = local.locations[each.value.location].region
  name_prefix = "${local.resource_prefix}-${each.value.role}${local.location_suffixes[each.value.location]}-"
  description = "OilScope ${each.value.role} role"
  vpc_id      = aws_vpc.main[each.value.location].id

  tags = merge(local.labels, {
    Name = "${local.resource_prefix}-${each.value.role}${local.location_suffixes[each.value.location]}"
    role = each.value.role
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "role" {
  for_each = local.role_instances

  region            = local.locations[each.value.location].region
  security_group_id = aws_security_group.role[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = local.bastion_cidrs

  region            = local.locations[each.value.location].region
  security_group_id = aws_security_group.role[each.value.location == var.config.default_location ? "bastion" : "${each.value.location}/bastion"].id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.ssh_port
  to_port           = each.value.ssh_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = local.bootstrap_bastion_cidrs

  region            = local.locations[each.value.location].region
  security_group_id = aws_security_group.role[each.value.location == var.config.default_location ? "bastion" : "${each.value.location}/bastion"].id
  cidr_ipv4         = each.value.cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = local.workload_role_instances

  region                       = local.locations[each.value.location].region
  security_group_id            = aws_security_group.role[each.key].id
  referenced_security_group_id = aws_security_group.role[each.value.location == var.config.default_location ? "bastion" : "${each.value.location}/bastion"].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = local.ui_ports

  region            = local.locations[each.value.location].region
  security_group_id = aws_security_group.role[each.value.location == var.config.default_location ? "ui" : "${each.value.location}/ui"].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
}
