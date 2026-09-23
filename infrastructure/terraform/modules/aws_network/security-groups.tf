resource "aws_security_group" "roles" {
  for_each = local.roles

  name_prefix = "${local.resource_prefix}-${each.value}-"
  description = "Access for ${each.value} VMs"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-${each.value}"
    role = each.value
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = aws_security_group.roles

  security_group_id = each.value.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = local.bastion_ssh_rules

  security_group_id = aws_security_group.roles["bastion"].id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "vms_ssh" {
  for_each = toset([
    for role in local.roles : role
    if role != "bastion" && contains(local.roles, "bastion")
  ])

  security_group_id            = aws_security_group.roles[each.value].id
  referenced_security_group_id = aws_security_group.roles["bastion"].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = {
    for port in var.config.network.ui_public_ports : tostring(port) => port
    if contains(local.roles, "ui")
  }

  security_group_id = aws_security_group.roles["ui"].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "history_api" {
  count = contains(local.roles, "ui") && contains(local.roles, "history") ? 1 : 0

  security_group_id            = aws_security_group.roles["history"].id
  referenced_security_group_id = aws_security_group.roles["ui"].id
  from_port                    = var.config.services.history.port
  to_port                      = var.config.services.history.port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rabbitmq" {
  for_each = toset([
    for role in local.roles : role
    if contains(["fetcher", "history"], role) && contains(local.roles, "infra")
  ])

  security_group_id            = aws_security_group.roles["infra"].id
  referenced_security_group_id = aws_security_group.roles[each.value].id
  from_port                    = var.config.services.rabbitmq.amqp_port
  to_port                      = var.config.services.rabbitmq.amqp_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "redis" {
  count = contains(local.roles, "ui") && contains(local.roles, "infra") ? 1 : 0

  security_group_id            = aws_security_group.roles["infra"].id
  referenced_security_group_id = aws_security_group.roles["ui"].id
  from_port                    = var.config.services.redis.port
  to_port                      = var.config.services.redis.port
  ip_protocol                  = "tcp"
}
