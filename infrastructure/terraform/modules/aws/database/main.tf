locals {
  engine_major = regex("^[0-9]+", var.managed_settings.engine_version)
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.resource_prefix}-postgres"
  subnet_ids = values(var.database_subnet_ids)

  tags = merge(var.tags, {
    Name = "${var.resource_prefix}-postgres"
  })

  lifecycle {
    precondition {
      condition     = length(var.database_subnet_ids) >= 2
      error_message = "Managed RDS PostgreSQL requires at least two database subnets in distinct Availability Zones."
    }
  }
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.resource_prefix}-postgres${local.engine_major}"
  family = "postgres${local.engine_major}"

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_cron"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "cron.database_name"
    value        = var.database.name
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.resource_prefix}-postgres"

  engine         = "postgres"
  engine_version = var.managed_settings.engine_version
  instance_class = var.managed_settings.instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.database.name
  username = var.database.user
  password = var.password
  port     = var.database.port

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false

  backup_retention_period      = 0
  copy_tags_to_snapshot        = true
  deletion_protection          = false
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${var.resource_prefix}-postgres-final"
  auto_minor_version_upgrade   = true
  apply_immediately            = true
  performance_insights_enabled = true

  tags = merge(var.tags, {
    Name = "${var.resource_prefix}-postgres"
  })
}
