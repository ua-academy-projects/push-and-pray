locals {
  enabled         = var.config.database_mode == "managed" && var.config.default_cloud == "aws"
  region          = var.config.locations[var.config.default_location].aws.region
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  labels          = merge(var.config.common_labels, { environment = var.config.environment })
}

resource "aws_db_subnet_group" "postgres" {
  count = local.enabled ? 1 : 0

  region     = local.region
  name       = "${local.resource_prefix}-postgres"
  subnet_ids = var.subnet_ids
  tags       = merge(local.labels, { Name = "${local.resource_prefix}-postgres" })
}

resource "aws_security_group" "postgres" {
  count = local.enabled ? 1 : 0

  region      = local.region
  name_prefix = "${local.resource_prefix}-postgres-"
  description = "Private access to the OilScope managed PostgreSQL database"
  vpc_id      = var.vpc_id
  tags        = merge(local.labels, { Name = "${local.resource_prefix}-postgres" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = local.enabled ? var.client_security_group_ids : {}

  region                       = local.region
  security_group_id            = aws_security_group.postgres[0].id
  referenced_security_group_id = each.value
  from_port                    = var.config.database.port
  to_port                      = var.config.database.port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "postgres" {
  count = local.enabled ? 1 : 0

  region            = local.region
  security_group_id = aws_security_group.postgres[0].id
  cidr_ipv4         = var.config.network.vpc_cidr
  ip_protocol       = "-1"
}

resource "aws_db_instance" "postgres" {
  count = local.enabled ? 1 : 0

  region                      = local.region
  identifier                  = "${local.resource_prefix}-postgres"
  engine                      = "postgres"
  engine_version              = var.config.database.postgres_version
  instance_class              = var.config.provider_mappings.database_sizes[var.config.database.size].aws.instance_class
  allocated_storage           = var.config.database.storage_gb
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.config.database.name
  username                    = var.config.database.admin_user
  port                        = var.config.database.port
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.postgres[0].name
  vpc_security_group_ids = [aws_security_group.postgres[0].id]
  publicly_accessible    = false
  multi_az               = var.config.environment == "prod"

  backup_retention_period    = var.config.environment == "prod" ? 7 : 1
  deletion_protection        = var.config.environment == "prod"
  skip_final_snapshot        = var.config.environment != "prod"
  final_snapshot_identifier  = var.config.environment == "prod" ? "${local.resource_prefix}-postgres-final" : null
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  apply_immediately          = var.config.environment != "prod"

  tags = merge(local.labels, { Name = "${local.resource_prefix}-postgres" })
}
