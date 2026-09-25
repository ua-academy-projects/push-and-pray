locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  agent_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  grants = {
    for pair in setproduct(keys(var.service_account_emails), local.agent_roles) :
    "${pair[0]}/${pair[1]}" => {
      account_name = pair[0]
      role         = pair[1]
    }
  }

  ui_vms = {
    for name, vm in var.vms : name => vm
    if vm.role == "ui"
  }

  system_alerts = {
    cpu = {
      display_name    = "VM CPU utilization"
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      threshold_value = var.config.monitoring.thresholds.cpu_percent / 100
      group_by_fields = ["resource.label.instance_id"]
    }
    memory = {
      display_name    = "VM memory utilization"
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"agent.googleapis.com/memory/percent_used\" AND metric.label.state = \"used\""
      threshold_value = var.config.monitoring.thresholds.memory_percent
      group_by_fields = ["resource.label.instance_id"]
    }
    disk = {
      display_name    = "VM disk utilization"
      filter          = "resource.type = \"gce_instance\" AND metric.type = \"agent.googleapis.com/disk/percent_used\" AND metric.label.state = \"used\""
      threshold_value = var.config.monitoring.thresholds.disk_percent
      group_by_fields = ["resource.label.instance_id"]
    }
    database_cpu = {
      display_name    = "Cloud SQL CPU utilization"
      filter          = "resource.type = \"cloudsql_database\" AND metric.type = \"cloudsql.googleapis.com/database/cpu/utilization\" AND resource.label.database_id = \"${var.config.gcp.project_id}:${local.resource_prefix}-postgresql\""
      threshold_value = var.config.monitoring.thresholds.cpu_percent / 100
      group_by_fields = ["resource.label.database_id"]
    }
    database_disk = {
      display_name    = "Cloud SQL disk utilization"
      filter          = "resource.type = \"cloudsql_database\" AND metric.type = \"cloudsql.googleapis.com/database/disk/utilization\" AND resource.label.database_id = \"${var.config.gcp.project_id}:${local.resource_prefix}-postgresql\""
      threshold_value = var.config.monitoring.thresholds.disk_percent / 100
      group_by_fields = ["resource.label.database_id"]
    }
  }
}
