resource "aws_db_subnet_group" "main" {
    count = local.enabled ? 1 : 0

    name = "${local.resource_prefix}-db"
    subnet_ids = var.database_subnet_ids
}

resource "aws_security_group" "rds" {
    count = local.enabled ? 1 : 0

    name = "${local.resource_prefix}-rds"
    vpc_id = var.vpc_id

    tags = {
        Name = "${local.resource_prefix}-rds"
    }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
    count = local.enabled ? 1 : 0

    security_group_id = aws_security_group.rds[0].id
    cidr_ipv4 = var.config.network.workload_subnet_cidr
    from_port = 5432
    to_port = 5432
    ip_protocol = "tcp"
}