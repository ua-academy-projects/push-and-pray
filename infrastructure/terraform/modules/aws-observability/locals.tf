locals {
  resource_prefix = var.config.name_prefix

  aws_vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      location = lookup(vm, "location", var.config.default_location)
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "aws"
  }

  regions = toset([
    for vm in values(local.aws_vms) :
    var.config.locations[vm.location].aws.region
  ])

  dashboard_region = try(sort(tolist(local.regions))[0], null)

  instance_ids_by_region = {
    for region in local.regions : region => {
      for name, vm in local.aws_vms : name => var.instance_ids[name]
      if var.config.locations[vm.location].aws.region == region
    }
  }

  dashboard_instance_ids = try(local.instance_ids_by_region[local.dashboard_region], {})

  dashboard_volume_ids = {
    for volume in flatten([
      for name, volumes in var.volume_ids : [
        for disk_name, volume_id in volumes : {
          key       = "${name}/${disk_name}"
          label     = "${local.resource_prefix}-${name}-${disk_name}"
          volume_id = volume_id
        }
        if var.config.locations[local.aws_vms[name].location].aws.region == local.dashboard_region
      ]
    ]) : volume.key => volume
  }

  notification_actions = {
    for region in local.regions : region => compact([
      try(var.config.monitoring.aws.notification_topic_arns[region], null),
    ])
  }

  metric_alarms = {
    for alarm in flatten([
      for region in local.regions : [
        {
          key                 = "${region}/cpu"
          region              = region
          name                = "${local.resource_prefix}-high-cpu"
          description         = "CPU utilization is above 80 percent on an OilScope EC2 instance."
          instance_ids        = local.instance_ids_by_region[region]
          namespace           = "AWS/EC2"
          metric_name         = "CPUUtilization"
          statistic           = "Average"
          dimensions          = {}
          comparison_operator = "GreaterThanThreshold"
          threshold           = 80
          evaluation_periods  = 3
          datapoints_to_alarm = 3
          treat_missing_data  = "notBreaching"
        },
        {
          key                 = "${region}/memory"
          region              = region
          name                = "${local.resource_prefix}-high-memory"
          description         = "Memory utilization is above 80 percent on an OilScope EC2 instance."
          instance_ids        = local.instance_ids_by_region[region]
          namespace           = "OilScope"
          metric_name         = "mem_used_percent"
          statistic           = "Average"
          dimensions          = {}
          comparison_operator = "GreaterThanThreshold"
          threshold           = 80
          evaluation_periods  = 3
          datapoints_to_alarm = 3
          treat_missing_data  = "notBreaching"
        },
        {
          key          = "${region}/disk"
          region       = region
          name         = "${local.resource_prefix}-high-disk-usage"
          description  = "Root disk utilization is above 80 percent on an OilScope EC2 instance."
          instance_ids = local.instance_ids_by_region[region]
          namespace    = "OilScope"
          metric_name  = "disk_used_percent"
          statistic    = "Average"
          dimensions = {
            path   = "/"
            fstype = "ext4"
          }
          comparison_operator = "GreaterThanThreshold"
          threshold           = 80
          evaluation_periods  = 3
          datapoints_to_alarm = 3
          treat_missing_data  = "notBreaching"
        },
        {
          key                 = "${region}/status"
          region              = region
          name                = "${local.resource_prefix}-status-check-failed"
          description         = "An OilScope EC2 instance failed an instance or system status check."
          instance_ids        = local.instance_ids_by_region[region]
          namespace           = "AWS/EC2"
          metric_name         = "StatusCheckFailed"
          statistic           = "Maximum"
          dimensions          = {}
          comparison_operator = "GreaterThanThreshold"
          threshold           = 0
          evaluation_periods  = 2
          datapoints_to_alarm = 2
          treat_missing_data  = "notBreaching"
        },
      ]
    ]) : alarm.key => alarm
  }

  aws_ui = {
    for name, vm in local.aws_vms : name => vm
    if contains(vm.tags, "ui")
  }

  dashboard_alarm_arns = concat(
    [for alarm in values(aws_cloudwatch_metric_alarm.vm) : alarm.arn],
    [for alarm in values(aws_cloudwatch_metric_alarm.http_5xx) : alarm.arn],
    [for alarm in values(aws_cloudwatch_metric_alarm.https) : alarm.arn],
  )
}
