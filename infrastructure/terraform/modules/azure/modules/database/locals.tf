locals {
  name = "${var.resource_prefix}-database"

  # Storage comes in fixed steps on Azure, not in any size; the configured
  # size is rounded up to the first step that holds it.
  storage_steps_mb = [32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4193280, 8388608, 16777216, 33553408]
  storage_mb = [
    for step in local.storage_steps_mb : step
    if step >= var.settings.storage_gb * 1024
  ][0]

  # Azure keeps backups for 7 to 35 days and cannot turn them off, so 0 and
  # anything below 7 - which the other clouds accept - become 7.
  backup_retention_days = min(max(var.settings.backup_retention_days, 7), 35)

  # The extensions the migrations create. Azure refuses any extension not on
  # this list, whoever asks for it.
  extensions = ["HSTORE", "PGCRYPTO"]

  # pg_cron is left out on purpose. The migrations create it wherever it is
  # preloaded, but Azure only lets it into the postgres database, not the
  # application's; sessions live in Redis in managed mode, so nothing needs it.
  preload_libraries = ["pg_stat_statements"]
}
