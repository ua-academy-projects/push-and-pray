output "hostname" {
  value = local.enabled ? local.hostname : null
}

output "tunnel_id" {
  value = local.enabled ? cloudflare_zero_trust_tunnel_cloudflared.this[0].id : null
}

output "tunnel_token" {
  value     = local.enabled ? cloudflare_zero_trust_tunnel_cloudflared.this[0].tunnel_token : null
  sensitive = true
}
