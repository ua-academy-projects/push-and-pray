locals {
  common_tags = merge(var.tags, {
    managed_by = "terraform"
    service    = "postgresql"
  })
  final_snapshot_identifier = coalesce(
    var.final_snapshot_identifier,
    "${var.name_prefix}-postgres-final",
  )
}

resource "aws_db_subnet_group" "this" {
  count = var.enabled ? 1 : 0

  name       = "${var.name_prefix}-postgres"
  subnet_ids = var.subnet_ids
  tags       = merge(local.common_tags, { Name = "${var.name_prefix}-postgres" })

  lifecycle {
    precondition {
      condition     = length(var.subnet_ids) >= 2
      error_message = "RDS requires private subnets in at least two Availability Zones."
    }
  }
}

resource "aws_security_group" "this" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.name_prefix}-rds-"
  description = "Private PostgreSQL access for OilScope"
  vpc_id      = var.vpc_id
  tags        = merge(local.common_tags, { Name = "${var.name_prefix}-rds" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = var.enabled ? var.allowed_security_group_ids : {}

  security_group_id            = aws_security_group.this[0].id
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from an OilScope workload"
}

resource "aws_db_parameter_group" "this" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.name_prefix}-postgres-"
  family      = var.parameter_group_family
  description = "OilScope PostgreSQL settings"
  tags        = local.common_tags

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pg_cron"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "cron.database_name"
    value        = var.database_name
    apply_method = "pending-reboot"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  count = var.enabled ? 1 : 0

  identifier = "${var.name_prefix}-postgres"

  engine                      = "postgres"
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage
  max_allocated_storage       = max(var.allocated_storage, 100)
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.database_name
  username                    = var.username
  manage_master_user_password = true
  port                        = var.port

  db_subnet_group_name   = aws_db_subnet_group.this[0].name
  vpc_security_group_ids = [aws_security_group.this[0].id]
  parameter_group_name   = aws_db_parameter_group.this[0].name
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  apply_immediately          = true
  copy_tags_to_snapshot      = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : local.final_snapshot_identifier

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-postgres" })

  lifecycle {
    precondition {
      condition     = var.clients_share_cloud
      error_message = "RDS clients must all select AWS until private cross-cloud routing exists."
    }
  }
}
