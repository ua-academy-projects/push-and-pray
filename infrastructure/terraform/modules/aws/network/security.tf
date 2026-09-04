resource "aws_security_group" "bastion" {
    name   = "${local.resource_prefix}-bastion"
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${local.resource_prefix}-bastion"
    }
}

resource "aws_security_group" "infra" {
    name   = "${local.resource_prefix}-infra"
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${local.resource_prefix}-infra"
    }
}

resource "aws_security_group" "history" {
    name   = "${local.resource_prefix}-history"
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${local.resource_prefix}-history"
    }
}

resource "aws_security_group" "fetcher" {
    name   = "${local.resource_prefix}-fetcher"
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${local.resource_prefix}-fetcher"
    }
}

resource "aws_security_group" "ui" {
    name   = "${local.resource_prefix}-ui"
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${local.resource_prefix}-ui"
    }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
    for_each = toset(var.bastion_allowed_cidrs)

    security_group_id = aws_security_group.bastion.id
    cidr_ipv4 = each.value
    from_port = var.bastion_ssh_port
    to_port  = var.bastion_ssh_port
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_bootstrap" {
    for_each = var.enable_bastion_ssh_bootstrap && var.bastion_ssh_port != 22 ? toset(var.bastion_allowed_cidrs) : toset([])

    security_group_id = aws_security_group.bastion.id
    cidr_ipv4 = each.value
    from_port = 22
    to_port = 22
    ip_protocol= "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
    for_each = {
        infra   = aws_security_group.infra.id
        history = aws_security_group.history.id
        fetcher = aws_security_group.fetcher.id
        ui = aws_security_group.ui.id
    }

    security_group_id = each.value
    referenced_security_group_id = aws_security_group.bastion.id
    from_port = 22
    to_port = 22
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
    for_each = toset(var.ui_public_ports)

    security_group_id = aws_security_group.ui.id
    cidr_ipv4 = "0.0.0.0/0"
    from_port = tonumber(each.value)
    to_port = tonumber(each.value)
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "history_api" {
    security_group_id = aws_security_group.history.id
    referenced_security_group_id = aws_security_group.ui.id
    from_port = var.history_api_port
    to_port = var.history_api_port
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
    for_each = {
        fetcher = aws_security_group.fetcher.id
        history = aws_security_group.history.id
        ui = aws_security_group.ui.id
    }

    security_group_id            = aws_security_group.infra.id
    referenced_security_group_id = each.value
    from_port = var.postgresql_port
    to_port = var.postgresql_port
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "bastion" {
    security_group_id = aws_security_group.bastion.id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "infra" {
    security_group_id = aws_security_group.infra.id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "history" {
    security_group_id = aws_security_group.history.id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "fetcher" {
    security_group_id = aws_security_group.fetcher.id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "ui" {
    security_group_id = aws_security_group.ui.id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}