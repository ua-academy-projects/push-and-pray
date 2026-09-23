resource "random_password" "database" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret_version" "database_password" {
  secret_id     = var.password_secret_arn
  secret_string = random_password.database.result
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.resource_prefix}-postgresql"
  subnet_ids = var.database_subnet_ids

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-postgresql"
  })
}

resource "aws_security_group" "database" {
  name_prefix = "${local.resource_prefix}-postgresql-"
  description = "Private PostgreSQL access"
  vpc_id      = var.vpc_id

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-postgresql"
    role = "database"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each = var.client_security_group_ids

  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = each.value
  from_port                    = var.config.services.database.port
  to_port                      = var.config.services.database.port
  ip_protocol                  = "tcp"
}

resource "aws_db_instance" "main" {
  identifier = "${local.resource_prefix}-postgresql"

  engine         = "postgres"
  engine_version = local.settings.engine_version
  instance_class = local.settings.instance_class

  db_name  = var.config.services.database.name
  username = var.config.services.database.username
  password = random_password.database.result
  port     = var.config.services.database.port

  allocated_storage = local.settings.allocated_storage_gb
  storage_type      = local.settings.storage_type
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = local.settings.multi_az

  backup_retention_period    = local.settings.backup_retention_days
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  apply_immediately          = var.config.environment == "dev"

  deletion_protection       = var.config.environment == "prod"
  skip_final_snapshot       = var.config.environment == "dev"
  final_snapshot_identifier = var.config.environment == "dev" ? null : "${local.resource_prefix}-postgresql-final"

  tags = merge(var.config.common_labels, {
    Name = "${local.resource_prefix}-postgresql"
  })

  depends_on = [aws_secretsmanager_secret_version.database_password]
}
