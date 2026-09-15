locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  labels = merge({
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }, var.config.common_labels)
  region = var.config.locations[var.config.default_location].aws.region
  instance_classes = {
    micro  = "db.t4g.micro"
    small  = "db.t4g.small"
    medium = "db.t4g.medium"
  }
}

resource "aws_db_subnet_group" "this" {
  region     = local.region
  name       = "${local.resource_prefix}-postgres"
  subnet_ids = var.network.database_subnet_ids
  tags       = local.labels
}

resource "aws_security_group" "postgresql" {
  region      = local.region
  name        = "${local.resource_prefix}-managed-postgresql"
  description = "Private access to the OilScope managed PostgreSQL instance"
  vpc_id      = var.network.vpc_id
  tags        = local.labels
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = toset(var.client_security_group_ids)

  region                       = local.region
  security_group_id            = aws_security_group.postgresql.id
  referenced_security_group_id = each.value
  from_port                    = var.config.service_ports.postgresql
  to_port                      = var.config.service_ports.postgresql
  ip_protocol                  = "tcp"
}

resource "aws_db_instance" "this" {
  region = local.region

  identifier             = "${local.resource_prefix}-postgres"
  engine                 = "postgres"
  engine_version         = var.config.database.version
  instance_class         = local.instance_classes[var.config.database.size]
  allocated_storage      = var.config.database.storage_gb
  max_allocated_storage  = var.config.database.storage_gb * 2
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = "oil_tracker"
  username               = "oil_tracker"
  password_wo            = var.password
  password_wo_version    = 1
  port                   = var.config.service_ports.postgresql
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.postgresql.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period   = var.config.environment == "dev" ? 0 : 7
  skip_final_snapshot       = var.config.environment == "dev"
  delete_automated_backups  = var.config.environment == "dev"
  deletion_protection       = var.config.environment != "dev"
  final_snapshot_identifier = var.config.environment == "dev" ? null : "${local.resource_prefix}-postgres-final"

  auto_minor_version_upgrade = true
  apply_immediately          = var.config.environment == "dev"
  copy_tags_to_snapshot      = true
  tags                       = local.labels
}

resource "aws_route53_zone" "internal" {
  name = "${local.resource_prefix}.internal"
  vpc {
    vpc_id     = var.network.vpc_id
    vpc_region = local.region
  }
  tags = local.labels
}

resource "aws_route53_record" "postgresql" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "postgres.${local.resource_prefix}.internal"
  type    = "CNAME"
  ttl     = 60
  records = [aws_db_instance.this.address]
}
