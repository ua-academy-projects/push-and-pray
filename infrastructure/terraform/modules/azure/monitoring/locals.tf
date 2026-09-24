locals {
  monitoring_enabled = length(var.vms) > 0
  resource_prefix    = "${var.config.name_prefix}-${var.config.environment}"
  labels             = merge(var.config.common_labels, { environment = var.config.environment })

  # Only locations containing actual Azure VMs need monitoring infrastructure.
  locations = {
    for location in toset([for vm in values(var.vms) : vm.location]) :
    location => var.config.locations[location].azure
  }
  location_suffixes = {
    for location in keys(local.locations) :
    location => location == var.config.default_location ? "" : "-${location}"
  }
  alerts_location = contains(keys(local.locations), var.config.default_location) ? var.config.default_location : try(sort(keys(local.locations))[0], null)

  # Azure platform metrics remain available independently of the guest agent.
  platform_alerts = {
    for alert in flatten([
      for name, vm in var.vms : [
        {
          key         = "${name}-cpu"
          vm          = vm
          suffix      = "cpu-high"
          description = "Average CPU utilization exceeds 80 percent over five minutes."
          metric_name = "Percentage CPU"
          operator    = "GreaterThan"
          threshold   = 80
          severity    = 2
        },
        {
          key         = "${name}-availability"
          vm          = vm
          suffix      = "availability-low"
          description = "Average VM availability is below 1 over five minutes."
          metric_name = "VmAvailabilityMetric"
          operator    = "LessThan"
          threshold   = 1
          severity    = 1
        },
      ]
    ]) : alert.key => alert
  }
}
