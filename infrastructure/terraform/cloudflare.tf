locals {
  cloudflare = merge({
    enabled    = false
    zone_id    = ""
    hostname   = ""
    proxied    = true
    acme_email = ""
  }, try(local.config.cloudflare, {}))

  ui_public_ips = compact([
    for vm in values(local.vm_outputs_by_name) : vm.public_ip if vm.role == "ui"
  ])
}

resource "cloudflare_dns_record" "ui" {
  count = local.cloudflare.enabled ? 1 : 0

  zone_id = local.cloudflare.zone_id
  name    = local.cloudflare.hostname
  content = local.ui_public_ips[0]
  type    = "A"
  ttl     = 1
  proxied = local.cloudflare.proxied

  comment = "Managed by Terraform: OilScope UI"

  lifecycle {
    precondition {
      condition     = length(local.ui_public_ips) == 1
      error_message = "Cloudflare requires exactly one UI VM with an assigned public IP."
    }
  }
}

resource "cloudflare_zone_setting" "ssl" {
  count = local.cloudflare.enabled ? 1 : 0

  zone_id    = local.cloudflare.zone_id
  setting_id = "ssl"
  value      = "strict"
}
