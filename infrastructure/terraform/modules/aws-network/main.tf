locals {
  roles = toset(["bastion", "database", "history", "fetcher", "ui"])
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.resource_prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-igw" })
}

resource "aws_subnet" "management" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.management_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.resource_prefix}-management" })
}

resource "aws_subnet" "workload" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.workload_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.resource_prefix}-workload" })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-nat-ip" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.management.id
  tags          = merge(var.tags, { Name = "${var.resource_prefix}-nat" })
}

resource "aws_route_table" "management" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-management" })
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

resource "aws_route_table" "workload" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-workload" })
}

resource "aws_route" "workload_internet" {
  route_table_id         = aws_route_table.workload.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "workload" {
  subnet_id      = aws_subnet.workload.id
  route_table_id = aws_route_table.workload.id
}

resource "aws_security_group" "role" {
  for_each = local.roles

  name_prefix = "${var.resource_prefix}-${each.key}-"
  description = "OilScope ${each.key} role"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.resource_prefix}-${each.key}"
    role = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "role" {
  for_each = local.roles

  security_group_id = aws_security_group.role[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.bastion_allowed_cidrs)

  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = each.value
  from_port         = var.bastion_ssh_port
  to_port           = var.bastion_ssh_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = var.enable_bastion_ssh_bootstrap && var.bastion_ssh_port != 22 ? toset(var.bastion_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = toset(["database", "history", "fetcher", "ui"])

  security_group_id            = aws_security_group.role[each.key].id
  referenced_security_group_id = aws_security_group.role["bastion"].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = toset([for port in var.ui_public_ports : tostring(port)])

  security_group_id = aws_security_group.role["ui"].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "history_api" {
  security_group_id            = aws_security_group.role["history"].id
  referenced_security_group_id = aws_security_group.role["ui"].id
  from_port                    = var.history_api_port
  to_port                      = var.history_api_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = toset(["fetcher", "history", "ui"])

  security_group_id            = aws_security_group.role["database"].id
  referenced_security_group_id = aws_security_group.role[each.value].id
  from_port                    = var.postgresql_port
  to_port                      = var.postgresql_port
  ip_protocol                  = "tcp"
}
