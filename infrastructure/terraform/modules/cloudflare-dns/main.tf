resource "cloudflare_dns_record" "ui" {
  zone_id = var.zone_id
  name    = var.hostname
  content = var.ipv4_address
  type    = "A"
  ttl     = 1
  proxied = false
  comment = "Managed by Terraform for the OilScope UI."
}
