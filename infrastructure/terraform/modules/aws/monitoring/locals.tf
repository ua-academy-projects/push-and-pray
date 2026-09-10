locals {
  period_seconds     = 60
  evaluation_periods = max(1, ceil(var.cpu.duration_seconds / local.period_seconds))
}
