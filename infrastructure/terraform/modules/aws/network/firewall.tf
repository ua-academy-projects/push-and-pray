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
