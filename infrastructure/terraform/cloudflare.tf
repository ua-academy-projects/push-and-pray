locals {
  public_endpoint_vm_entries = {
    for name, vm in local.config.vms : name => vm
    if try(vm.public_endpoint.hostname, null) != null
  }
  public_endpoint_vm_name = try(one(keys(local.public_endpoint_vm_entries)), null)
  public_endpoint_vm = try(
    merge(module.gcp_vm.vms, module.aws_vm.vms, merge({}, [for regional_module in values(module.azure_vm) : regional_module.vms]...))[local.public_endpoint_vm_name],
    null,
  )
  public_endpoint_hostname = try(
    local.public_endpoint_vm_entries[local.public_endpoint_vm_name].public_endpoint.hostname,
    null,
  )
  cloudflare_ui_dns_enabled = (
    var.cloudflare_zone_id != null &&
    length(local.public_endpoint_vm_entries) == 1
  )
}

check "single_public_endpoint" {
  assert {
    condition = (
      var.cloudflare_zone_id == null ||
      length(local.public_endpoint_vm_entries) == 1
    )
    error_message = "Exactly one VM with public_endpoint is required when Cloudflare DNS is enabled."
  }
}

resource "cloudflare_dns_record" "ui" {
  count = local.cloudflare_ui_dns_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = local.public_endpoint_hostname
  type    = "A"
  content = try(local.public_endpoint_vm.public_ip, null)
  ttl     = var.cloudflare_dns_ttl
  proxied = var.cloudflare_dns_proxied
  comment = "OilScope ingress; managed by Terraform"

  lifecycle {
    precondition {
      condition     = local.public_endpoint_hostname != null && trimspace(local.public_endpoint_hostname) != ""
      error_message = "The public endpoint VM must define public_endpoint.hostname."
    }

    precondition {
      condition = (
        try(local.public_endpoint_vm.public_ip, null) != null &&
        can(cidrnetmask("${local.public_endpoint_vm.public_ip}/32"))
      )
      error_message = "The public endpoint VM must have a valid public IPv4 address."
    }

    precondition {
      condition     = !var.cloudflare_dns_proxied || var.cloudflare_dns_ttl == 1
      error_message = "A proxied Cloudflare record must use automatic TTL (1)."
    }
  }
}
