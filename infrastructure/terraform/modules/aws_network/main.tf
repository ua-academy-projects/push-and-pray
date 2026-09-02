resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-vpc"
    },
  )
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-igw"
    },
  )
}

resource "aws_subnet" "management" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.management_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-management"
      Type = "public"
    },
  )
}

resource "aws_subnet" "workload" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.workload_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-workload"
      Type = "private"
    },
  )
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-nat-ip"
    },
  )
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.management.id

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-nat"
    },
  )

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "management" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-management"
    },
  )
}

resource "aws_route_table_association" "management" {
  subnet_id      = aws_subnet.management.id
  route_table_id = aws_route_table.management.id
}

resource "aws_route_table" "workload" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []

    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-workload"
    },
  )
}

resource "aws_route_table_association" "workload" {
  subnet_id      = aws_subnet.workload.id
  route_table_id = aws_route_table.workload.id
}

resource "aws_security_group" "bastion" {
  name        = "${var.resource_prefix}-bastion"
  description = "Bastion access"
  vpc_id      = aws_vpc.main.id

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
  vpc_id      = aws_vpc.main.id

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
  vpc_id      = aws_vpc.main.id

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
  vpc_id      = aws_vpc.main.id

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
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-ui"
      role = "ui"
    },
  )
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.bastion_allowed_cidrs)

  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = each.value
  from_port         = var.bastion_ssh_port
  to_port           = var.bastion_ssh_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_bootstrap" {
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
    for port in var.ui_public_ports :
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
  from_port                    = var.history_api_port
  to_port                      = var.history_api_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_history" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.history.id
  from_port                    = var.postgresql_port
  to_port                      = var.postgresql_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_fetcher" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.fetcher.id
  from_port                    = var.postgresql_port
  to_port                      = var.postgresql_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_ui" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.ui.id
  from_port                    = var.postgresql_port
  to_port                      = var.postgresql_port
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

resource "aws_vpc_security_group_ingress_rule" "ui_direct_ssh" {
  for_each = (
    var.enable_ui_direct_ssh
    ? toset(var.bastion_allowed_cidrs)
    : toset([])
  )

  security_group_id = aws_security_group.ui.id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}
