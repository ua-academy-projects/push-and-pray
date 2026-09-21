locals {
  settings = var.config.cloudflare

  ui_vm_keys = [
    for key, vm in var.config.vms : key
    if vm.role == "ui" && coalesce(vm.cloud, var.config.default_cloud) == var.config.default_cloud
  ]
  ui_vm_key = one(local.ui_vm_keys)

  hostname = try(var.config.vms[local.ui_vm_key].public_endpoint.hostname, "")

  public_ips = {
    aws = { for name, vm in var.aws_vms : name => vm.public_ip }
    gcp = { for name, vm in var.gcp_vms : name => vm.public_ip }
  }
  ip_address = coalesce(try(local.public_ips[var.config.default_cloud][local.ui_vm_key], ""), "")
}

data "cloudflare_zone" "selected" {
  count  = local.settings.enabled ? 1 : 0
  filter = { name = local.settings.zone_name }
}

resource "cloudflare_dns_record" "ui" {
  count   = local.settings.enabled ? 1 : 0
  zone_id = data.cloudflare_zone.selected[0].zone_id
  name    = local.hostname
  type    = "A"
  content = local.ip_address
  # Grey cloud. Traefik's TLS-ALPN-01 challenge has to reach the origin on
  # :443; see the `proxied` validation in variables.tf before changing this.
  proxied = local.settings.proxied
  # 60s by default: the address is a reserved EIP/static address and so is
  # stable in normal operation, but a destroy/re-apply allocates a new one,
  # and a short TTL bounds how long resolvers answer with the dead address.
  ttl     = local.settings.ttl
  comment = local.settings.comment != "" ? local.settings.comment : "OilScope UI ingress, managed by Terraform"

  lifecycle {
    precondition {
      condition     = local.ui_vm_key != null
      error_message = "Cloudflare DNS is enabled but the configuration has no VM with role \"ui\" in default_cloud, so there is nothing to publish."
    }

    precondition {
      condition     = length(local.hostname) > 0
      error_message = "Cloudflare DNS is enabled but the UI VM defines no public_endpoint.hostname."
    }

    precondition {
      condition     = local.hostname == local.settings.zone_name || endswith(local.hostname, ".${local.settings.zone_name}")
      error_message = "The UI VM's public_endpoint.hostname must sit inside cloudflare.zone_name; a name in another zone cannot be created from this zone's ID."
    }

    precondition {
      condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", local.ip_address))
      error_message = "Cloudflare DNS is enabled but the default_cloud UI VM has no public IPv4 address; check that its assign_public_ip is true."
    }
  }
}

output "summary" {
  description = "What the record publishes, for `terraform output -json dns`."
  value = local.settings.enabled ? {
    id       = cloudflare_dns_record.ui[0].id
    hostname = local.hostname
    zone     = local.settings.zone_name
    address  = local.ip_address
    ttl      = local.settings.ttl
    proxied  = local.settings.proxied
  } : null
}
