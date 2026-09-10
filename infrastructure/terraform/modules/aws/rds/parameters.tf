resource "aws_db_parameter_group" "main" {
    count = local.enabled ? 1 : 0

    name   = "${local.resource_prefix}-pg"
    family = "postgres${var.config.managed_db.version.aws}"

    parameter {
        name = "shared_preload_libraries"
        value = "pg_cron"
        apply_method = "pending-reboot"
    }

    parameter {
        name = "cron.database_name"
        value = local.db_name
        apply_method = "pending-reboot"
    }
}