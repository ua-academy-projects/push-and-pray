resource "aws_security_group" "bastion" {
  name        = "${var.resource_prefix}-bastion"
  description = "Bastion access"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-bastion"
      role = "bastion"
    },
  )
}

resource "aws_security_group" "database" {
  name        = "${var.resource_prefix}-database"
  description = "Database workload"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-database"
      role = "database"
    },
  )
}

resource "aws_security_group" "history" {
  name        = "${var.resource_prefix}-history"
  description = "History workload"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-history"
      role = "history"
    },
  )
}

resource "aws_security_group" "fetcher" {
  name        = "${var.resource_prefix}-fetcher"
  description = "Fetcher workload"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-fetcher"
      role = "fetcher"
    },
  )
}

resource "aws_security_group" "ui" {
  name        = "${var.resource_prefix}-ui"
  description = "UI workload"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-ui"
      role = "ui"
    },
  )
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.policy.bastion_allowed_cidrs)

  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = each.value
  from_port         = var.policy.bastion_ssh_port
  to_port           = var.policy.bastion_ssh_port
  ip_protocol       = "tcp"
}

locals {
  workload_security_groups = {
    database = aws_security_group.database.id
    history  = aws_security_group.history.id
    fetcher  = aws_security_group.fetcher.id
    ui       = aws_security_group.ui.id
  }
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
  for_each = local.workload_security_groups

  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
  for_each = toset([
    for port in var.policy.ui_public_ports :
    tostring(port)
  ])

  security_group_id = aws_security_group.ui.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "history_from_ui" {
  security_group_id            = aws_security_group.history.id
  referenced_security_group_id = aws_security_group.ui.id
  from_port                    = var.policy.history_api_port
  to_port                      = var.policy.history_api_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_history" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.history.id
  from_port                    = var.policy.postgresql_port
  to_port                      = var.policy.postgresql_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_fetcher" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.fetcher.id
  from_port                    = var.policy.postgresql_port
  to_port                      = var.policy.postgresql_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_ui" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.ui.id
  from_port                    = var.policy.redis_port
  to_port                      = var.policy.redis_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rabbitmq_from_apps" {
  for_each = var.policy.rabbitmq_enabled ? {
    history = aws_security_group.history.id
    fetcher = aws_security_group.fetcher.id
  } : {}

  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = each.value
  from_port                    = var.policy.rabbitmq_port
  to_port                      = var.policy.rabbitmq_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "bastion" {
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "workloads" {
  for_each = local.workload_security_groups

  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
