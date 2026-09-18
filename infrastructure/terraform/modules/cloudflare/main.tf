resource "random_id" "tunnel_secret" {
  count       = local.enabled ? 1 : 0
  byte_length = 35
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  count      = local.enabled ? 1 : 0
  account_id = var.config.cloudflare.account_id
  name       = try(var.config.cloudflare.tunnel_name, "oilscope")
  secret     = random_id.tunnel_secret[0].b64_std
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  count      = local.enabled ? 1 : 0
  account_id = var.config.cloudflare.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this[0].id

  config {
    ingress_rule {
      hostname = local.hostname
      service  = try(var.config.cloudflare.service, "http://ui:8080")
      origin_request {
        origin_server_name = local.hostname
      }
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}

data "cloudflare_zone" "this" {
  count = local.enabled ? 1 : 0
  name  = var.config.cloudflare.zone
}

resource "cloudflare_record" "tunnel" {
  count   = local.enabled ? 1 : 0
  zone_id = data.cloudflare_zone.this[0].id
  name    = var.config.cloudflare.record_name
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this[0].id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}
