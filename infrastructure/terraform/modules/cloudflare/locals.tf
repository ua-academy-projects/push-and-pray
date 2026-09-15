locals {
  enabled  = try(var.config.cloudflare.enabled, false)
  hostname = "${try(var.config.cloudflare.record_name, "")}.${try(var.config.cloudflare.zone, "")}"
}
