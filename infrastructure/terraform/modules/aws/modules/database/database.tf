# The managed PostgreSQL. Lives in the database subnets, admits the three
# workloads and the infra instance on its port, and nothing else. The default
# parameter group of this engine family already forces TLS, so clients set
# sslmode=require and no custom group is needed.
resource "aws_db_subnet_group" "main" {
  name        = local.name
  description = "Subnets the managed database is reachable in"
  subnet_ids  = var.subnet_ids

  tags = merge(var.tags, { Name = local.name })
}

resource "aws_security_group" "database" {
  name        = local.name
  description = "Managed PostgreSQL"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = local.name })
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each = var.client_security_group_ids

  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = each.value
  description                  = "PostgreSQL from ${each.key}"

  ip_protocol = "tcp"
  from_port   = var.port
  to_port     = var.port

  tags = var.tags
}

# The master password is generated and kept by RDS in Secrets Manager, so it
# never passes through Terraform. Ansible copies it into the project's own
# secret container afterwards; see the managed_database_credentials playbook.
resource "aws_db_instance" "main" {
  identifier     = local.name
  engine         = "postgres"
  engine_version = var.settings.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.settings.storage_gb
  max_allocated_storage = var.settings.storage_gb * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.settings.name
  username = var.settings.username
  port     = var.port

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = var.settings.backup_retention_days
  copy_tags_to_snapshot   = true

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately           = true

  deletion_protection       = var.settings.deletion_protection
  skip_final_snapshot       = !var.settings.deletion_protection
  final_snapshot_identifier = var.settings.deletion_protection ? "${local.name}-final" : null

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(var.tags, { Name = local.name })
}
