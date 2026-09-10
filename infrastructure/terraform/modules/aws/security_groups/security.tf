resource "aws_security_group" "bastion" {
    count = local.bastion != null ? 1 : 0

    name   = "${local.resource_prefix}-bastion"
    vpc_id = var.vpc_id

    tags = {
        Name = "${local.resource_prefix}-bastion"
    }
}

resource "aws_security_group" "infra" {
    count = local.tag_present["infra"] ? 1 : 0

    name   = "${local.resource_prefix}-infra"
    vpc_id = var.vpc_id

    tags = {
        Name = "${local.resource_prefix}-infra"
    }
}

resource "aws_security_group" "history" {
    count = local.tag_present["history"] ? 1 : 0

    name   = "${local.resource_prefix}-history"
    vpc_id = var.vpc_id

    tags = {
        Name = "${local.resource_prefix}-history"
    }
}

resource "aws_security_group" "fetcher" {
    count = local.tag_present["fetcher"] ? 1 : 0

    name   = "${local.resource_prefix}-fetcher"
    vpc_id = var.vpc_id

    tags = {
        Name = "${local.resource_prefix}-fetcher"
    }
}

resource "aws_security_group" "ui" {
    count = local.tag_present["ui"] ? 1 : 0

    name   = "${local.resource_prefix}-ui"
    vpc_id = var.vpc_id

    tags = {
        Name = "${local.resource_prefix}-ui"
    }
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
    for_each = local.bastion_ssh_rules

    security_group_id = aws_security_group.bastion[0].id
    cidr_ipv4 = each.value.cidr
    from_port = each.value.port
    to_port  = each.value.port
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "workload_ssh" {
    for_each = local.bastion != null ? toset(local.workload_tags_present) : toset([])

    security_group_id = (
        each.value == "infra"   ? aws_security_group.infra[0].id :
        each.value == "history" ? aws_security_group.history[0].id :
        each.value == "fetcher" ? aws_security_group.fetcher[0].id :
        aws_security_group.ui[0].id
    )
    referenced_security_group_id = aws_security_group.bastion[0].id
    from_port = 22
    to_port = 22
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ui_web" {
    for_each = local.tag_present["ui"] ? toset(local.ui_public_ports_str) : toset([])

    security_group_id = aws_security_group.ui[0].id
    cidr_ipv4 = "0.0.0.0/0"
    from_port = tonumber(each.value)
    to_port = tonumber(each.value)
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "history_api" {
    count = local.tag_present["history"] && local.tag_present["ui"] ? 1 : 0

    security_group_id = aws_security_group.history[0].id
    referenced_security_group_id = aws_security_group.ui[0].id
    from_port = var.config.service_ports.history_api
    to_port = var.config.service_ports.history_api
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
    for_each = local.tag_present["infra"] ? {
        for role in ["fetcher", "history", "ui"] : role => (
            role == "fetcher" ? aws_security_group.fetcher[0].id :
            role == "history" ? aws_security_group.history[0].id :
            aws_security_group.ui[0].id
        )
        if local.tag_present[role]
    } : {}

    security_group_id            = aws_security_group.infra[0].id
    referenced_security_group_id = each.value
    from_port = var.config.service_ports.postgresql
    to_port = var.config.service_ports.postgresql
    ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "bastion" {
    count = local.bastion != null ? 1 : 0

    security_group_id = aws_security_group.bastion[0].id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "infra" {
    count = local.tag_present["infra"] ? 1 : 0

    security_group_id = aws_security_group.infra[0].id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "history" {
    count = local.tag_present["history"] ? 1 : 0

    security_group_id = aws_security_group.history[0].id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "fetcher" {
    count = local.tag_present["fetcher"] ? 1 : 0

    security_group_id = aws_security_group.fetcher[0].id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}

resource "aws_vpc_security_group_egress_rule" "ui" {
    count = local.tag_present["ui"] ? 1 : 0

    security_group_id = aws_security_group.ui[0].id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}
