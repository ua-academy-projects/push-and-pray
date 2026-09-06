resource "aws_security_group" "scope" {
  for_each = toset(local.scopes)

  name        = "${var.resource_prefix}-${each.value}"
  description = "Traffic allowed to the ${each.value} scope"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.resource_prefix}-${each.value}" })
}

# A GCP network permits all egress unless a rule denies it; an AWS security
# group permits none unless a rule allows it. This restores the GCP behaviour
# these rules were written against.
resource "aws_vpc_security_group_egress_rule" "allow_all" {
  for_each = aws_security_group.scope

  security_group_id = each.value.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.bastion_allowed_cidrs)

  security_group_id = aws_security_group.scope["bastion"].id
  cidr_ipv4         = each.value

  ip_protocol = "tcp"
  from_port   = var.bastion_ssh_port
  to_port     = var.bastion_ssh_port

  tags = var.tags
}

# A fresh bastion listens on 22 until Ansible installs the final sshd policy.
# This rule must be explicitly enabled and removed immediately after bootstrap.
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = (
    var.enable_bastion_ssh_bootstrap && var.bastion_ssh_port != 22
    ? toset(var.bastion_allowed_cidrs)
    : toset([])
  )

  security_group_id = aws_security_group.scope["bastion"].id
  cidr_ipv4         = each.value

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = toset(local.workload_scopes)

  security_group_id            = aws_security_group.scope[each.value].id
  referenced_security_group_id = aws_security_group.scope["bastion"].id

  ip_protocol = "tcp"
  from_port   = 22
  to_port     = 22

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = toset(var.ui_public_ports)

  security_group_id = aws_security_group.scope["ui"].id
  cidr_ipv4         = "0.0.0.0/0"

  ip_protocol = "tcp"
  from_port   = tonumber(each.value)
  to_port     = tonumber(each.value)

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "history_api" {
  security_group_id            = aws_security_group.scope["history"].id
  referenced_security_group_id = aws_security_group.scope["ui"].id

  ip_protocol = "tcp"
  from_port   = var.history_api_port
  to_port     = var.history_api_port

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = toset(local.database_client_scopes)

  security_group_id            = aws_security_group.scope["infra"].id
  referenced_security_group_id = aws_security_group.scope[each.value].id

  ip_protocol = "tcp"
  from_port   = var.postgresql_port
  to_port     = var.postgresql_port

  tags = var.tags
}
