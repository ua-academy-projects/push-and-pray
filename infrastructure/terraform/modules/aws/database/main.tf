resource "aws_db_subnet_group" "this" {
  count = local.enabled ? 1 : 0

  name       = "${local.resource_prefix}-database"
  subnet_ids = var.network.rds_subnet_ids
}

resource "aws_security_group" "rds" {
  count = local.enabled ? 1 : 0

  name        = "${local.resource_prefix}-rds-sg"
  description = "Allows PostgreSQL connections from application services"
  vpc_id      = var.network.vpc_id

  ingress {
    description = "PostgreSQL from Fetcher and History"
    from_port   = var.config.service_ports.postgresql
    to_port     = var.config.service_ports.postgresql
    protocol    = "tcp"

    security_groups = [
      var.network.security_group_ids.fetcher,
      var.network.security_group_ids.history,
    ]
  }
}

resource "aws_db_parameter_group" "this" {
  count = local.enabled ? 1 : 0

  name   = "${local.resource_prefix}-postgres${local.settings.engine_version}"
  family = "postgres${local.settings.engine_version}"

  # Server-side encryption enforcement complements client-side verify-full.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "this" {
  count = local.enabled ? 1 : 0

  identifier     = "${local.resource_prefix}-database"
  engine         = "postgres"
  engine_version = local.settings.engine_version
  instance_class = local.settings.instance_class

  allocated_storage     = local.settings.allocated_storage_gb
  storage_type          = local.settings.storage_type
  max_allocated_storage = local.settings.max_allocated_storage_gb
  multi_az              = local.settings.multi_az
  availability_zone     = local.settings.multi_az ? null : var.config.region_map[var.config.region].aws.availability_zone

  db_name  = "oil_tracker"
  port     = var.config.service_ports.postgresql
  username = "oil_tracker_admin"
  # RDS generates the administrator password; Terraform stores only its reference.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this[0].name
  vpc_security_group_ids = [aws_security_group.rds[0].id]
  parameter_group_name   = aws_db_parameter_group.this[0].name
  publicly_accessible    = false
  storage_encrypted      = true

  backup_retention_period = local.settings.backup_retention_days
  # A mode switch intentionally discards this database, including managed backups.
  deletion_protection         = false
  skip_final_snapshot         = true
  delete_automated_backups    = true
  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = true

  tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}
