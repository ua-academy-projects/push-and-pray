locals {
  roles = toset(["bastion", "database", "history", "fetcher", "ui"])
}

resource "aws_security_group" "role" {
  for_each = local.roles

  name        = "${var.resource_prefix}-${each.key}"
  description = "OilScope ${each.key} traffic"
  vpc_id      = var.vpc_id

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
  count = var.enable_bastion_nat ? 1 : 0

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
