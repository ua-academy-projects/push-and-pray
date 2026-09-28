locals {
  resource_prefix = var.config.name_prefix

  service_account_roles = {
    for grant in flatten([
      for vm_name in keys(local.gcp_vms) : [
        for role in var.writer_roles : {
          key   = "${vm_name}/${role}"
          email = var.service_account_emails[vm_name]
          role  = role
        }
      ]
    ]) : grant.key => grant
  }

  gcp_workload_vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
  }

  gcp_bastion_vms = lookup(var.config.bastion, "cloud", var.config.default_cloud) == "gcp" ? {
    bastion = merge(var.config.bastion, {
      tags = ["bastion"]
    })
  } : {}

  gcp_vms = merge(local.gcp_workload_vms, local.gcp_bastion_vms)

  gcp_ui = {
    for name, vm in local.gcp_workload_vms : name => vm
    if contains(vm.tags, "ui")
  }

  notification_channels = compact([
    try(var.config.monitoring.gcp.notification_channel_id, null),
  ])

  monitoring_instance_filter = join(" OR ", [
    for instance_id in values(var.instance_ids) :
    "resource.label.instance_id=\"${instance_id}\""
  ])

  logging_instance_filter = join(" OR ", [
    for name, instance_id in var.instance_ids :
    "resource.labels.instance_id=\"${instance_id}\""
    if contains(keys(local.gcp_workload_vms), name)
  ])

  vm_metric_alerts = {
    cpu = {
      display_name         = "${local.resource_prefix}-high-cpu"
      condition_name       = "CPU utilization above 80 percent"
      metric_filter        = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
      threshold            = 0.8
      cross_series_reducer = null
      group_by_fields      = []
    }
    memory = {
      display_name         = "${local.resource_prefix}-high-memory"
      condition_name       = "Memory utilization above 80 percent"
      metric_filter        = "metric.type=\"agent.googleapis.com/memory/percent_used\" AND metric.label.state=\"used\""
      threshold            = 80
      cross_series_reducer = null
      group_by_fields      = []
    }
    disk = {
      display_name         = "${local.resource_prefix}-high-disk-usage"
      condition_name       = "Root disk utilization above 80 percent"
      metric_filter        = "metric.type=\"agent.googleapis.com/disk/percent_used\" AND metric.label.state=\"used\" AND metric.label.device=\"/dev/sda1\""
      threshold            = 80
      cross_series_reducer = null
      group_by_fields      = []
    }
  }
}
