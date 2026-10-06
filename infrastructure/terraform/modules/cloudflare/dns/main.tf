locals {
  headlamp_published = var.config.headlamp.enabled && var.config.headlamp.hostname != ""

  records = merge(
    {
      ingress = var.config.ingress.hostname
      api     = var.config.kubernetes.api_endpoint
    },
    local.headlamp_published ? { headlamp = var.config.headlamp.hostname } : {}
  )
}

data "cloudflare_zone" "selected" {
  count  = var.config.cloudflare.enabled ? 1 : 0
  filter = { name = var.config.cloudflare.zone_name }
}

resource "cloudflare_dns_record" "entry" {
  for_each = var.config.cloudflare.enabled ? local.records : {}

  zone_id = data.cloudflare_zone.selected[0].zone_id
  name    = each.value
  type    = "A"
  content = var.vm.vms[var.config.kubernetes.entry_node].public_ip
  proxied = var.config.cloudflare.proxied
  ttl     = var.config.cloudflare.ttl

  comment = (
    var.config.cloudflare.comment != ""
    ? var.config.cloudflare.comment
    : "OilScope ${each.key} on ${var.config.kubernetes.entry_node}, managed by Terraform"
  )
}
