output "summary" {
  description = "The records published for the entry node, or null when DNS is managed by hand."
  value = var.config.cloudflare.enabled ? {
    for key, record in cloudflare_dns_record.entry : key => {
      id         = record.id
      hostname   = record.name
      zone       = var.config.cloudflare.zone_name
      address    = record.content
      ttl        = record.ttl
      proxied    = record.proxied
      entry_node = var.config.kubernetes.entry_node
    }
  } : null
}

output "headlamp" {
  description = "The operator console's hostname and the address it must resolve to. managed is false when Cloudflare is disabled or the console is off, in which case the A record is created by hand; see docs/headlamp.md."
  value = {
    enabled  = var.config.headlamp.enabled
    hostname = local.headlamp_published ? var.config.headlamp.hostname : null
    address  = var.vm.vms[var.config.kubernetes.entry_node].public_ip
    managed  = var.config.cloudflare.enabled && local.headlamp_published
  }
}
