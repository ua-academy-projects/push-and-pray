# Native OTel counters are distinct from legacy performanceCounters/Perf logs.
resource "azapi_resource" "metrics_dcr" {
  for_each = local.locations

  type      = "Microsoft.Insights/dataCollectionRules@2024-03-11"
  name      = "${local.resource_prefix}-dcr-metrics${local.location_suffixes[each.key]}"
  parent_id = split("/providers/", azurerm_monitor_workspace.metrics[each.key].id)[0]
  location  = each.value.region
  tags      = local.labels

  # Older AzAPI 2.x embedded schemas omit these documented OTel properties.
  schema_validation_enabled = false

  body = {
    kind = "Linux"
    properties = {
      description = "OilScope Linux guest OpenTelemetry metrics sampled every minute."
      dataSources = {
        performanceCountersOTel = [{
          name                       = "linux-guest-metrics"
          streams                    = ["Microsoft-OtelPerfMetrics"]
          samplingFrequencyInSeconds = 60
          counterSpecifiers = [
            "system.cpu.time",
            "system.filesystem.usage",
            "system.uptime",
          ]
        }]
      }
      destinations = {
        monitoringAccounts = [{
          name              = "metrics"
          accountResourceId = azurerm_monitor_workspace.metrics[each.key].id
        }]
      }
      dataFlows = [{
        streams      = ["Microsoft-OtelPerfMetrics"]
        destinations = ["metrics"]
      }]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "metrics" {
  for_each = var.vms

  name                    = "${local.resource_prefix}-metrics"
  target_resource_id      = each.value.resource_id
  data_collection_rule_id = azapi_resource.metrics_dcr[each.value.location].id
  description             = "Collect Linux guest metrics into the regional Azure Monitor workspace."

  depends_on = [azurerm_virtual_machine_extension.ama]
}
