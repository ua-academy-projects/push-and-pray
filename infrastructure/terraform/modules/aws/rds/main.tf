resource "random_password" "db" {
    count = local.enabled ? 1 : 0
    length = 32
    special = false
}

resource "aws_db_instance" "main" {
    count = local.enabled ? 1 : 0

    identifier        = "${local.resource_prefix}-postgres"
    engine            = "postgres"
    engine_version = var.config.managed_db.version.aws
    instance_class = var.config.managed_db.tier.aws
    allocated_storage = var.config.managed_db.disk_size_gb

    db_name = local.db_name
    username = local.db_user
    password = random_password.db[0].result

    db_subnet_group_name = aws_db_subnet_group.main[0].name
    vpc_security_group_ids = [aws_security_group.rds[0].id]
    parameter_group_name = aws_db_parameter_group.main[0].name

    publicly_accessible = false
    multi_az            = false
    skip_final_snapshot = true
    deletion_protection = false
}

resource "aws_secretsmanager_secret_version" "db_password" {
    count = local.enabled ? 1 : 0

    secret_id = var.db_password_secret_id
    secret_string = random_password.db[0].result
}