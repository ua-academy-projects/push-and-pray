resource "aws_security_group" "tag" {
  for_each = local.tags

  region = each.value.region
  name   = "${local.context.resource_prefix}-${each.value.location}-${each.value.tag}"
  vpc_id = var.networks[each.value.location].vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.context.labels, { Name = "${local.context.resource_prefix}-${each.value.location}-${each.value.tag}" })
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = local.bastion_ssh_rules

  region            = var.networks[each.value.location].region
  security_group_id = aws_security_group.tag["${each.value.location}/bastion"].id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = local.workload_ssh_rules

  region                       = each.value.region
  security_group_id            = aws_security_group.tag[each.key].id
  referenced_security_group_id = aws_security_group.tag["${each.value.location}/bastion"].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = local.ui_rules

  region            = each.value.region
  security_group_id = aws_security_group.tag[each.value.tag_key].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "history_api" {
  for_each = local.history_rules

  region                       = each.value.region
  security_group_id            = aws_security_group.tag["${each.key}/history"].id
  referenced_security_group_id = aws_security_group.tag["${each.key}/ui"].id
  from_port                    = var.config.service_ports.history_api
  to_port                      = var.config.service_ports.history_api
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = local.postgresql_rules

  region                       = each.value.region
  security_group_id            = aws_security_group.tag["${each.value.location}/infrastructure"].id
  referenced_security_group_id = aws_security_group.tag[each.key].id
  from_port                    = var.config.service_ports.postgresql
  to_port                      = var.config.service_ports.postgresql
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rabbitmq" {
  for_each = local.rabbitmq_rules

  region                       = each.value.region
  security_group_id            = aws_security_group.tag["${each.value.location}/infrastructure"].id
  referenced_security_group_id = aws_security_group.tag[each.key].id
  from_port                    = var.config.service_ports.rabbitmq
  to_port                      = var.config.service_ports.rabbitmq
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "redis" {
  for_each = local.redis_rules

  region                       = each.value.region
  security_group_id            = aws_security_group.tag["${each.value.location}/infrastructure"].id
  referenced_security_group_id = aws_security_group.tag[each.key].id
  from_port                    = var.config.service_ports.redis
  to_port                      = var.config.service_ports.redis
  ip_protocol                  = "tcp"
}
