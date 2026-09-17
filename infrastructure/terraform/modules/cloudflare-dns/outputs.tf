output "record" {
  description = "Provider-neutral DNS record contract."
  value = {
    id       = cloudflare_dns_record.ui.id
    hostname = var.hostname
    type     = "A"
    content  = var.ipv4_address
    proxied  = var.proxied
    ttl      = var.ttl
  }
}
