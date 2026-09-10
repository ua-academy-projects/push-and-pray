# Exported configurations are installed by VM deployment, not Terraform provisioners.
locals {
  agent_configurations = {
    for name, vm in var.vms : name => jsonencode(merge(
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
      local.logs_enabled && contains(keys(local.ui_vms), name) ? {
        logs = { logs_collected = { files = { collect_list = [{
          file_path       = "/var/log/oilscope/traefik-access.log"
          log_group_name  = local.log_group_name
          log_stream_name = "{instance_id}"
        }] } } }
      } : {}
    )) if local.agent_enabled || (local.logs_enabled && contains(keys(local.ui_vms), name))
  }
}
