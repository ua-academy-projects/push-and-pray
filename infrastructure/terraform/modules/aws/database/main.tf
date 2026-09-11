locals {
  identifier = "${var.resource_prefix}-postgres-${var.generation}"
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.identifier}-subnets"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${local.identifier}-subnets" })

  lifecycle {
    precondition {
      condition     = length(var.subnet_ids) >= 2
      error_message = "RDS requires database subnets in at least two Availability Zones."
    }
  }
}

resource "aws_security_group" "this" {
  name_prefix = "${local.identifier}-"
  description = "Private PostgreSQL access for OilScope workloads"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${local.identifier}-database" })
}

resource "aws_vpc_security_group_ingress_rule" "workloads" {
  for_each = var.workload_security_group_ids

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "PostgreSQL from ${each.key} workloads"
}

resource "aws_vpc_security_group_ingress_rule" "remote_workloads" {
  for_each = var.remote_workload_cidrs

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "PostgreSQL from private cross-cloud workloads"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_db_instance" "this" {
  identifier = local.identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage      = var.allocated_storage_gb
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = var.database_name
  username               = var.username
  password               = var.password
  port                   = var.port
  multi_az               = var.multi_az
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]

  backup_retention_period  = var.backups_enabled ? 7 : 0
  skip_final_snapshot      = !var.backup_on_delete
  delete_automated_backups = !var.backup_on_delete
  deletion_protection      = var.deletion_protection
  snapshot_identifier      = var.snapshot_identifier

  copy_tags_to_snapshot = true
  apply_immediately     = true
  tags                  = merge(var.tags, { Name = local.identifier })

  lifecycle {
    create_before_destroy = true
  }
}
