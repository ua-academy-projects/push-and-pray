locals {
  config = jsondecode(file(var.project_config_path))

  cloudflare = merge({
    enabled    = false
    zone_id    = ""
    hostname   = ""
    proxied    = true
    acme_email = ""
  }, try(local.config.cloudflare, {}))
}
