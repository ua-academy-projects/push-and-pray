resource "aws_security_group" "vm" {
  for_each = local.vms

  name_prefix = "${local.resource_prefix}-${each.key}-"
  description = "OilScope ${each.value.role} VM"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.resource_prefix}-${each.key}"
      role = each.value.role
    },
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = aws_security_group.vm

  security_group_id = each.value.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = local.bastion_ssh_rules

  security_group_id = aws_security_group.vm[each.value.vm_name].id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = local.workload_ssh_targets

  security_group_id            = aws_security_group.vm[each.key].id
  referenced_security_group_id = aws_security_group.vm[local.bastion_name].id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = local.ui_web_rules

  security_group_id = aws_security_group.vm[each.value.vm_name].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value.port
  to_port           = each.value.port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "history_api" {
  for_each = local.history_api_rules

  security_group_id            = aws_security_group.vm[each.value.target].id
  referenced_security_group_id = aws_security_group.vm[each.value.source].id
  from_port                    = var.config.service_ports.history_api
  to_port                      = var.config.service_ports.history_api
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = local.postgresql_rules

  security_group_id            = aws_security_group.vm[each.value.target].id
  referenced_security_group_id = aws_security_group.vm[each.value.source].id
  from_port                    = var.config.service_ports.postgresql
  to_port                      = var.config.service_ports.postgresql
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rabbitmq" {
  for_each = local.rabbitmq_rules

  security_group_id            = aws_security_group.vm[each.value.target].id
  referenced_security_group_id = aws_security_group.vm[each.value.source].id
  from_port                    = try(var.config.service_ports.rabbitmq, 5672)
  to_port                      = try(var.config.service_ports.rabbitmq, 5672)
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_bootstrap" {
  for_each = {
    for key, rule in local.bastion_ssh_rules : key => rule
    if var.enable_bastion_ssh_bootstrap && rule.port != 22
  }
  security_group_id = aws_security_group.vm[each.value.vm_name].id
  cidr_ipv4         = each.value.cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}
