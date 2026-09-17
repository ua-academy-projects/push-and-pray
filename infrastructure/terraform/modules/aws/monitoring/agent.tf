# Exported configurations are installed by VM deployment, not Terraform provisioners.
locals {
  agent_configurations = {
    for name, vm in local.workload_vms : name => jsonencode(merge(
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
  log_files = { for name, vm in local.workload_vms : name => concat(
    local.logs_enabled && contains(keys(local.ui_vms), name) ? [{ file_path = "/var/log/oilscope/traefik-access.log", log_group_name = local.log_group_name, log_stream_name = "{instance_id}" }] : [],
    local.service_logs_enabled ? [for service in lookup({ ui = ["ui", "traefik", "redis"], history = ["history", "rabbitmq"], fetcher = ["fetcher"], database = ["postgres"] }, var.config.vms[name].role, []) : { file_path = "/var/log/oilscope/docker-${service}.log", log_group_name = local.application_log_group, log_stream_name = "{instance_id}/${service}" }] : [],
    local.application_enabled ? [{ file_path = "/var/log/oilscope/application-metrics.jsonl", log_group_name = local.application_log_group, log_stream_name = "{instance_id}/metrics" }] : []
  ) }
}
