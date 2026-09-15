locals {
  name = "${var.resource_prefix}-database"

  backups_enabled = var.settings.backup_retention_days > 0

  # Cloud SQL keeps transaction logs for point-in-time recovery for one to
  # seven days; the configured retention is clamped into that range.
  transaction_log_retention_days = min(max(var.settings.backup_retention_days, 1), 7)
}
