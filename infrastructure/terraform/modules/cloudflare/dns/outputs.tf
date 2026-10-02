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
