resource "aws_subnet" "database" {
  count = 2

  vpc_id                  = var.vpc_id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.resource_prefix}-database-${count.index + 1}"
    Type = "private-database"
  })
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.resource_prefix}-postgres"
  subnet_ids = aws_subnet.database[*].id
  tags       = var.tags
}

resource "aws_route_table_association" "database" {
  count = 2

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = var.private_route_table_id
}

resource "aws_security_group" "database" {
  name        = "${var.resource_prefix}-rds"
  description = "Private PostgreSQL access from OilScope applications"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  for_each = var.application_sg_ids

  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = each.value
  from_port                    = var.database_port
  to_port                      = var.database_port
  ip_protocol                  = "tcp"
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.resource_prefix}-postgres16"
  family = "postgres16"

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_cron"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "cron.database_name"
    value        = var.database_name
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

resource "aws_db_instance" "this" {
  identifier             = "${var.resource_prefix}-postgres"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = var.database_name
  username               = var.database_user
  password               = var.password
  port                   = var.database_port
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.database.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  tags                   = var.tags
}
