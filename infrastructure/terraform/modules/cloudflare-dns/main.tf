resource "cloudflare_dns_record" "ui" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "A"
  content = var.ipv4_address
  proxied = var.proxied
  ttl     = var.ttl
  comment = "Managed by Terraform for OilScope"
}
