
resource "aws_security_group" "bastion" {
  name        = "${var.resource_prefix}-bastion"
  description = "Bastion host"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.resource_prefix}-bastion" })
}

resource "aws_security_group" "infra" {
  name        = "${var.resource_prefix}-infra"
  description = "Database workload"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.resource_prefix}-infra" })
}

resource "aws_security_group" "history" {
  name        = "${var.resource_prefix}-history"
  description = "History workload"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.resource_prefix}-history" })
}

resource "aws_security_group" "fetcher" {
  name        = "${var.resource_prefix}-fetcher"
  description = "Fetcher workload"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.resource_prefix}-fetcher" })
}

resource "aws_security_group" "ui" {
  name        = "${var.resource_prefix}-ui"
  description = "UI workload"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, { Name = "${var.resource_prefix}-ui" })
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.bastion_allowed_cidrs)

  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = each.value
  from_port         = var.bastion_ssh_port
  to_port           = var.bastion_ssh_port
  ip_protocol       = "tcp"
  description       = "Operator SSH to the bastion"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = (
    var.enable_bastion_ssh_bootstrap && var.bastion_ssh_port != 22
    ? toset(var.bastion_allowed_cidrs)
    : toset([])
  )

  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "Temporary bootstrap SSH to the bastion"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = local.workload_groups

  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  description                  = "SSH from the bastion"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = toset(var.ui_public_ports)

  security_group_id = aws_security_group.ui.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
  description       = "Public HTTPS to the UI"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "history_api" {
  security_group_id            = aws_security_group.history.id
  referenced_security_group_id = aws_security_group.ui.id
  from_port                    = var.history_api_port
  to_port                      = var.history_api_port
  ip_protocol                  = "tcp"
  description                  = "History API from the UI"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = {
    fetcher = aws_security_group.fetcher.id
    history = aws_security_group.history.id
    ui      = aws_security_group.ui.id
  }

  security_group_id            = aws_security_group.infra.id
  referenced_security_group_id = each.value
  from_port                    = var.postgresql_port
  to_port                      = var.postgresql_port
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from ${each.key}"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  for_each = merge(local.workload_groups, { bastion = aws_security_group.bastion.id })

  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Egress through the NAT gateway"

  tags = var.tags
}
