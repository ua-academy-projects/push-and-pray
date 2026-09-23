locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  namespace       = "OilScope/${var.config.environment}"
  log_group_name  = "/oilscope/${var.config.environment}/journald"

  ui_vms = {
    for name, vm in var.vms : name => vm
    if vm.role == "ui"
  }

  vm_alarm_metrics = {
    cpu = {
      metric_name = "cpu_usage_active"
      threshold   = var.config.monitoring.thresholds.cpu_percent
    }
    memory = {
      metric_name = "mem_used_percent"
      threshold   = var.config.monitoring.thresholds.memory_percent
    }
    disk = {
      metric_name = "disk_used_percent"
      threshold   = var.config.monitoring.thresholds.disk_percent
    }
  }

  vm_alarms = merge([
    for vm_name, vm in var.vms : {
      for metric_key, metric in local.vm_alarm_metrics :
      "${vm_name}/${metric_key}" => merge(metric, {
        vm_name     = vm_name
        instance_id = vm.instance_id
      })
    }
  ]...)

  region                 = var.config.regions[var.config.location].aws
  availability_alarm_arn = local.region == "us-east-1" ? aws_sns_topic.alerts.arn : aws_sns_topic.availability[0].arn
}
