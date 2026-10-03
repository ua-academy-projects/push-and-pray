locals {
  # Every platform metric the dashboard shows and alerting watches, in one
  # place. The platform collects them for every VM without an agent. Alerts
  # look at a five-minute window, so totals are scaled to it here and nowhere
  # else; rates and averages are compared as they are.
  window_minutes = 5

  metrics = {
    cpu = {
      title       = "CPU utilization (%)"
      name        = "Percentage CPU"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.thresholds.cpu_utilization * 100
    }
    disk_write = {
      title       = "OS disk write operations per second"
      name        = "OS Disk Write Operations/Sec"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = var.thresholds.disk_write_ops_per_second
    }
    network_in = {
      title       = "Network bytes received per ${local.window_minutes} minutes"
      name        = "Network In Total"
      aggregation = "Total"
      operator    = "GreaterThan"
      threshold   = var.thresholds.network_received_mbit_per_second * 125000 * 60 * local.window_minutes
    }
    # 1 while the VM answers the platform's health checks. A deallocated VM
    # reports nothing at all, which a metric alert cannot see; the resource
    # health alert in alerting covers that case.
    health = {
      title       = "VM availability"
      name        = "VmAvailabilityMetric"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = 1
    }
  }

  # The portal's own codes for an aggregation.
  aggregation_codes = {
    Total   = 1
    Minimum = 2
    Maximum = 3
    Average = 4
  }
}

# One chart per metric, one line per VM. Memory is not among them: it comes
# from the agent into the workspace, not from the platform, and the memory
# alert queries it there.
resource "azurerm_portal_dashboard" "hosts" {
  name                = "${var.resource_prefix}-hosts"
  resource_group_name = var.resource_group_name
  location            = var.location

  dashboard_properties = jsonencode({
    lenses = {
      "0" = {
        order = 0
        parts = {
          for index, name in keys(local.metrics) : tostring(index) => {
            position = {
              x       = index % 2 * 6
              y       = floor(index / 2) * 4
              colSpan = 6
              rowSpan = 4
            }
            metadata = {
              type = "Extension/HubsExtension/PartType/MonitorChartPart"
              inputs = [
                { name = "options", isOptional = true },
                { name = "sharedTimeRange", isOptional = true },
              ]
              settings = {
                content = {
                  options = {
                    chart = {
                      title         = local.metrics[name].title
                      titleKind     = 2
                      visualization = { chartType = 2 }
                      metrics = [
                        for instance in values(var.instances) : {
                          resourceMetadata    = { id = instance.id }
                          name                = local.metrics[name].name
                          aggregationType     = local.aggregation_codes[local.metrics[name].aggregation]
                          namespace           = "microsoft.compute/virtualmachines"
                          metricVisualization = { displayName = instance.name }
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    metadata = {
      model = {
        timeRange = {
          type  = "MsPortalFx.Composition.Configuration.ValueTypes.TimeRange"
          value = { relative = { duration = 24, timeUnit = 1 } }
        }
      }
    }
  })

  tags = var.tags
}
