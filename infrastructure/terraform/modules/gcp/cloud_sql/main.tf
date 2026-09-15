resource "random_password" "db" {
    count = local.enabled ? 1 : 0
    length = 32
    special = false
}

resource "google_sql_database_instance" "main" {
    count = local.enabled ? 1 : 0

    name = "${local.resource_prefix}-postgres"
    database_version = var.config.managed_db.version.gcp
    region = var.config.regions[var.config.region].gcp.region
    deletion_protection = false

    settings {
        tier = var.config.managed_db.tier.gcp
        disk_size = var.config.managed_db.disk_size_gb
        availability_type = "ZONAL"

        ip_configuration {
            ipv4_enabled = false
            private_network = var.network_self_link
        }

        database_flags {
            name = "cloudsql.enable_pg_cron"
            value = "on"
        }
        database_flags {
        name  = "cron.database_name"
        value = local.db_name
        }
    }
}

resource "google_sql_database" "main" {
    count = local.enabled ? 1 : 0

    name = local.db_name
    instance = google_sql_database_instance.main[0].name
}

resource "google_sql_user" "main" {
    count = local.enabled ? 1 : 0

    name = local.db_user
    instance = google_sql_database_instance.main[0].name
    password = random_password.db[0].result
}

resource "google_secret_manager_secret_version" "db_password" {
    count = local.enabled ? 1 : 0

    secret = var.db_password_secret_id
    secret_data = random_password.db[0].result
}