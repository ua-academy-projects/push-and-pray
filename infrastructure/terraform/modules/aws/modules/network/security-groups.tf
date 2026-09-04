locals {
  security_group_descriptions = {
    bastion  = "Bastion access"
    database = "Database server access"
    history  = "History service access"
    fetcher  = "Fetcher service access"
    ui       = "Public UI access"
  }

  workload_ssh_roles = toset([
    "database",
    "history",
    "fetcher",
    "ui",
  ])

  postgresql_source_roles = toset([
    "history",
    "fetcher",
    "ui",
  ])
}

resource "aws_security_group" "role" {
  for_each = local.security_group_descriptions

  name_prefix = "${var.resource_prefix}-${each.key}-"
  description = each.value
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.resource_prefix}-${each.key}"
    role = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = aws_security_group.role

  security_group_id = each.value.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  description = "Allow outbound traffic"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.bastion_allowed_cidrs)

  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = each.value
  from_port         = var.bastion_ssh_port
  to_port           = var.bastion_ssh_port
  ip_protocol       = "tcp"

  description = "Final bastion SSH access"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = var.bastion_ssh_port == 22 ? toset([]) : toset(var.bastion_allowed_cidrs)

  security_group_id = aws_security_group.role["bastion"].id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"

  description = "Initial Ansible SSH access"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = local.workload_ssh_roles

  security_group_id            = aws_security_group.role[each.value].id
  referenced_security_group_id = aws_security_group.role["bastion"].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"

  description = "SSH from bastion"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = {
    for port in var.ui_public_ports : tostring(port) => port
  }

  security_group_id = aws_security_group.role["ui"].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"

  description = "Public UI port ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "history_api" {
  security_group_id            = aws_security_group.role["history"].id
  referenced_security_group_id = aws_security_group.role["ui"].id
  from_port                    = var.history_api_port
  to_port                      = var.history_api_port
  ip_protocol                  = "tcp"

  description = "History API from UI"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = local.postgresql_source_roles

  security_group_id            = aws_security_group.role["database"].id
  referenced_security_group_id = aws_security_group.role[each.value].id
  from_port                    = var.postgresql_port
  to_port                      = var.postgresql_port
  ip_protocol                  = "tcp"

  description = "PostgreSQL from ${each.value}"
}