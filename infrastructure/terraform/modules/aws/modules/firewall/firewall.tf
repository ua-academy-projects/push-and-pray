resource "aws_security_group" "scope" {
  for_each = toset(local.scopes)

  name        = "${var.resource_prefix}-${each.value}"
  description = "Traffic allowed to the ${each.value} scope"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.resource_prefix}-${each.value}" })
}

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  for_each = aws_security_group.scope

  security_group_id = each.value.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.bastion.allowed_cidrs)

  security_group_id = aws_security_group.scope["bastion"].id
  cidr_ipv4         = each.value

  ip_protocol = "tcp"
  from_port   = var.bastion.ssh_port
  to_port     = var.bastion.ssh_port

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
  for_each = (
    var.enable_bastion_ssh_bootstrap && var.bastion.ssh_port != 22
    ? toset(var.bastion.allowed_cidrs)
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
  for_each = toset(local.ui_public_ports)

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
  from_port   = var.config.service_ports.history_api
  to_port     = var.config.service_ports.history_api

  tags = var.tags
}

# What the infra instance serves depends on where the database runs.
# Self-hosted: PostgreSQL. Managed: the RabbitMQ broker and the Redis cache
# that take over the queue and the sessions. The clients are the same three
# workloads either way; the managed database has a security group of its own
# in the database module.
resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = var.database_managed ? toset([]) : toset(local.database_client_scopes)

  security_group_id            = aws_security_group.scope["infra"].id
  referenced_security_group_id = aws_security_group.scope[each.value].id

  ip_protocol = "tcp"
  from_port   = var.config.service_ports.postgresql
  to_port     = var.config.service_ports.postgresql

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "amqp" {
  for_each = var.database_managed ? toset(local.database_client_scopes) : toset([])

  security_group_id            = aws_security_group.scope["infra"].id
  referenced_security_group_id = aws_security_group.scope[each.value].id

  ip_protocol = "tcp"
  from_port   = var.config.service_ports.amqp
  to_port     = var.config.service_ports.amqp

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "redis" {
  for_each = var.database_managed ? toset(local.database_client_scopes) : toset([])

  security_group_id            = aws_security_group.scope["infra"].id
  referenced_security_group_id = aws_security_group.scope[each.value].id

  ip_protocol = "tcp"
  from_port   = var.config.service_ports.redis
  to_port     = var.config.service_ports.redis

  tags = var.tags
}
