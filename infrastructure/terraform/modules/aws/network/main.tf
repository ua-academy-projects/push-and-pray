locals {
  roles = toset(["bastion", "database", "history", "fetcher", "ui"])
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${var.resource_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-igw" })
}

resource "aws_subnet" "management" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.management_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.resource_prefix}-management" })
}

resource "aws_subnet" "workload" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.workload_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.resource_prefix}-workload" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = "${var.resource_prefix}-public" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "management" {
  subnet_id      = aws_subnet.management.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "workload" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.resource_prefix}-workload" })
}

resource "aws_route_table_association" "workload" {
  subnet_id      = aws_subnet.workload.id
  route_table_id = aws_route_table.workload.id
}

resource "aws_security_group" "role" {
  for_each = local.roles

  name        = "${var.resource_prefix}-${each.key}"
  description = "OilScope ${each.key} traffic"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.resource_prefix}-${each.key}" })
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = var.enable_bastion ? toset(var.bastion_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = each.value
  from_port         = var.bastion_ssh_port
  to_port           = var.bastion_ssh_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = var.enable_bastion && var.enable_bastion_ssh_bootstrap && var.bastion_ssh_port != 22 ? toset(var.bastion_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_nat_from_workloads" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = var.workload_subnet_cidr
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = toset(["database", "history", "fetcher", "ui"])

  security_group_id            = aws_security_group.role[each.value].id
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
