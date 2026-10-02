locals {
  agent_configurations = {
    for name, vm in local.nodes : name => jsonencode(merge(
      { agent = { metrics_collection_interval = 60 } },
      local.agent_enabled ? {
        metrics = {
          namespace         = "CWAgent"
          append_dimensions = { InstanceId = "$${aws:InstanceId}" }
          metrics_collected = {
            mem  = { measurement = ["mem_used_percent"] }
            disk = { measurement = ["used_percent"], resources = ["/"], drop_device = true }
          }
        }
      } : {},
      length(local.log_files[name]) > 0 ? {
        logs = { logs_collected = { files = { collect_list = local.log_files[name] } } }
      } : {}
    )) if local.agent_enabled || length(local.log_files[name]) > 0
  }

  log_files = { for name, vm in local.nodes : name => concat(
    local.application_enabled ? [{ file_path = "/var/log/oilscope/application-metrics.jsonl", log_group_name = local.application_log_group, log_stream_name = "{instance_id}/metrics" }] : []
  ) }
}
