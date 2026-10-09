locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  azure_workloads = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "azure"
  }
  azure_bastion_enabled = lookup(
    var.config.bastion,
    "cloud",
    var.config.default_cloud,
  ) == "azure"
  azure_instance_names = concat(
    keys(local.azure_workloads),
    local.azure_bastion_enabled ? ["bastion"] : [],
  )
  azure_instance_ids = {
    for name in local.azure_instance_names : name => var.instance_ids[name]
  }
  enabled          = length(local.azure_workloads) > 0 || local.azure_bastion_enabled
  shared_resources = local.enabled ? { main = true } : {}
  tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  azure_ui = {
    for name, vm in local.azure_workloads : name => vm
    if contains(vm.tags, "ui")
  }

  action_group_ids = [for action_group in values(azurerm_monitor_action_group.this) : action_group.id]

  expected_resource_ids = join(", ", [
    for instance_id in values(local.azure_instance_ids) : jsonencode(lower(instance_id))
  ])

  workbook_metric_panels = [
    {
      title  = "VM CPU credits remaining"
      metric = "CPU Credits Remaining"
    },
  ]

  workbook_queries = [
    {
      title         = "VM CPU utilization"
      query         = <<-KQL
        Perf
        | where ObjectName == "Processor" and CounterName == "% Processor Time" and InstanceName == "total"
        | summarize Value=avg(CounterValue) by bin(TimeGenerated, 5m), Computer
        | render timechart
      KQL
      visualization = "timechart"
      aggregation   = 3
      chart_settings = {
        showLegend = true
        ySettings = {
          min = 0
          max = 100
          numberFormatSettings = {
            unit = 1
            options = {
              style                 = "decimal"
              useGrouping           = true
              minimumFractionDigits = 0
              maximumFractionDigits = 1
            }
          }
        }
      }
    },
    {
      title         = "VM memory utilization"
      query         = <<-KQL
        Perf
        | where ObjectName == "Memory" and CounterName == "% Used Memory"
        | summarize Value=avg(CounterValue) by bin(TimeGenerated, 5m), Computer
        | render timechart
      KQL
      visualization = "timechart"
      aggregation   = 3
      chart_settings = {
        showLegend = true
        ySettings = {
          min = 0
          max = 100
          numberFormatSettings = {
            unit = 1
            options = {
              style                 = "decimal"
              useGrouping           = true
              minimumFractionDigits = 0
              maximumFractionDigits = 1
            }
          }
        }
      }
    },
    {
      title         = "VM root disk utilization"
      query         = <<-KQL
        Perf
        | where ObjectName == "Logical Disk" and CounterName == "% Used Space" and InstanceName == "/"
        | summarize Value=avg(CounterValue) by bin(TimeGenerated, 5m), Computer
        | render timechart
      KQL
      visualization = "timechart"
      aggregation   = 3
      chart_settings = {
        showLegend = true
        ySettings = {
          min = 0
          max = 100
          numberFormatSettings = {
            unit = 1
            options = {
              style                 = "decimal"
              useGrouping           = true
              minimumFractionDigits = 0
              maximumFractionDigits = 1
            }
          }
        }
      }
    },
    {
      title         = "VM network throughput (bytes/sec)"
      query         = <<-KQL
        Perf
        | where ObjectName == "Network" and CounterName in ("Total Bytes Received", "Total Bytes Transmitted")
        | project TimeGenerated, Computer, CounterName, InstanceName, CounterValue
        | extend Series=strcat(Computer, "|", CounterName, "|", InstanceName)
        | sort by Series asc, TimeGenerated asc
        | serialize
        | extend PreviousSeries=prev(Series), PreviousValue=prev(CounterValue), PreviousTime=prev(TimeGenerated)
        | where Series == PreviousSeries
        | extend ElapsedSeconds=datetime_diff("millisecond", TimeGenerated, PreviousTime) / 1000.0
        | extend BytesPerSecond=(CounterValue - PreviousValue) / ElapsedSeconds
        | where ElapsedSeconds > 0 and BytesPerSecond >= 0
        | summarize InterfaceBytesPerSecond=avg(BytesPerSecond) by bin(TimeGenerated, 5m), Computer, CounterName, InstanceName
        | summarize Value=sum(InterfaceBytesPerSecond) by TimeGenerated, Computer
        | render timechart
      KQL
      visualization = "timechart"
      aggregation   = 3
      chart_settings = {
        showLegend = true
        ySettings = {
          min = 0
          numberFormatSettings = {
            unit = 36
            options = {
              style                 = "decimal"
              useGrouping           = true
              minimumFractionDigits = 0
              maximumFractionDigits = 1
            }
          }
        }
      }
    },
    {
      title         = "VM root disk operations (ops/sec)"
      query         = <<-KQL
        Perf
        | where ObjectName == "Logical Disk" and CounterName in ("Disk Reads/sec", "Disk Writes/sec") and InstanceName == "/"
        | summarize CounterOpsPerSecond=avg(CounterValue) by bin(TimeGenerated, 5m), Computer, CounterName
        | summarize Value=sum(CounterOpsPerSecond) by TimeGenerated, Computer
        | render timechart
      KQL
      visualization = "timechart"
      aggregation   = 3
      chart_settings = {
        showLegend = true
        ySettings = {
          min = 0
        }
      }
    },
    {
      title          = "Azure Monitor Agent heartbeat"
      query          = <<-KQL
        Heartbeat
        | summarize LastHeartbeat=max(TimeGenerated) by Computer
        | extend MinutesSinceHeartbeat=datetime_diff("minute", now(), LastHeartbeat)
        | project Computer, LastHeartbeat, MinutesSinceHeartbeat
        | order by MinutesSinceHeartbeat desc
      KQL
      visualization  = "table"
      aggregation    = 0
      chart_settings = null
    },
    {
      title         = "HTTP requests"
      query         = <<-KQL
        Syslog
        | where Facility == "local0" and SyslogMessage contains "RequestMethod"
        | summarize Requests=count() by bin(TimeGenerated, 1h)
        | render timechart
      KQL
      visualization = "timechart"
      aggregation   = 0
      chart_settings = {
        showLegend = true
        ySettings = {
          min = 0
        }
      }
    },
    {
      title         = "HTTPS availability"
      query         = <<-KQL
        AppAvailabilityResults
        | summarize Availability=100.0 * countif(Success) / count() by bin(TimeGenerated, 15m), Name
        | render timechart
      KQL
      visualization = "timechart"
      aggregation   = 3
      chart_settings = {
        showLegend = true
        ySettings = {
          min = 0
          max = 100
          numberFormatSettings = {
            unit = 1
            options = {
              style                 = "decimal"
              useGrouping           = true
              minimumFractionDigits = 0
              maximumFractionDigits = 1
            }
          }
        }
      }
    },
    {
      title          = "Recent HTTP 5xx responses"
      query          = <<-KQL
        Syslog
        | where Facility == "local0" and SyslogMessage matches regex @"DownstreamStatus[^0-9]*5[0-9]{2}[^0-9]"
        | project TimeGenerated, Computer, SyslogMessage
        | order by TimeGenerated desc
        | take 50
      KQL
      visualization  = "table"
      aggregation    = 0
      chart_settings = null
    },
  ]
}
