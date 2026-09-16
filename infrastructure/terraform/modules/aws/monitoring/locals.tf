locals {
  period_seconds          = 60
  evaluation_periods      = max(1, ceil(var.settings.cpu.duration_seconds / local.period_seconds))
  disk_evaluation_periods = max(1, ceil(var.settings.disk.duration_seconds / local.period_seconds))
  log_group_name          = "/${var.resource_prefix}/docker"
}
