locals {
  agent_configurations = {
    for name, vm in var.vms : name => yamlencode({
      logging = {
        service = { pipelines = merge({ default_pipeline = { receivers = [] } }, local.logs_enabled && contains(keys(local.ui_vms), name) ? {
          oilscope_access = { receivers = ["oilscope_access"], processors = ["oilscope_json"] }
        } : {}) }
        receivers = local.logs_enabled && contains(keys(local.ui_vms), name) ? {
          oilscope_access = { type = "files", include_paths = ["/var/log/oilscope/traefik-access.log"] }
        } : {}
        processors = local.logs_enabled && contains(keys(local.ui_vms), name) ? {
          oilscope_json = { type = "parse_json" }
        } : {}
      }
      metrics = {
        receivers = { hostmetrics = { type = "hostmetrics", collection_interval = "60s" } }
        service   = { pipelines = { default_pipeline = { receivers = local.agent_enabled ? ["hostmetrics"] : [] } } }
      }
    }) if local.agent_enabled || (local.logs_enabled && contains(keys(local.ui_vms), name))
  }
}
