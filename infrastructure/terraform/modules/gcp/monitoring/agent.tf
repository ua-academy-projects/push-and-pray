locals {
  agent_configurations = {
    for name, vm in local.workload_vms : name => yamlencode({
      logging = {
        service = { pipelines = merge({ default_pipeline = { receivers = [] } }, local.logs_enabled && contains(keys(local.ui_vms), name) ? {
          oilscope_access = { receivers = ["oilscope_access"], processors = ["oilscope_json"] }
        } : {}, local.service_logs_enabled ? { oilscope_services = { receivers = ["oilscope_services"], processors = ["oilscope_json"] } } : {}) }
        receivers = merge(local.logs_enabled && contains(keys(local.ui_vms), name) ? {
          oilscope_access = { type = "files", include_paths = ["/var/log/oilscope/traefik-access.log"] }
        } : {}, local.service_logs_enabled ? { oilscope_services = { type = "files", include_paths = ["/var/lib/docker/containers/*/*-json.log"] } } : {})
        processors = local.service_logs_enabled || (local.logs_enabled && contains(keys(local.ui_vms), name)) ? {
          oilscope_json = { type = "parse_json" }
        } : {}
      }
      metrics = {
        receivers = { hostmetrics = { type = "hostmetrics", collection_interval = "60s" } }
        service   = { pipelines = { default_pipeline = { receivers = local.agent_enabled ? ["hostmetrics"] : [] } } }
      }
    }) if local.service_logs_enabled || local.agent_enabled || (local.logs_enabled && contains(keys(local.ui_vms), name))
  }
}
