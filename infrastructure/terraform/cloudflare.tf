locals {
  ui_vm_entries = {
    for name, vm in local.config.vms : name => vm
    if vm.role == "ui"
  }
  ui_vm_name = try(one(keys(local.ui_vm_entries)), null)
  ui_vm      = try(merge(module.gcp_vm.vms, module.aws_vm.vms)[local.ui_vm_name], null)
  ui_hostname = try(
    local.ui_vm_entries[local.ui_vm_name].public_endpoint.hostname,
    null,
  )
  cloudflare_ui_dns_enabled = var.cloudflare_zone_id != null
}

check "single_ui_workload" {
  assert {
    condition     = length(local.ui_vm_entries) == 1
    error_message = "Exactly one VM with role=ui is required."
  }
}

resource "cloudflare_dns_record" "ui" {
  count = local.cloudflare_ui_dns_enabled ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = local.ui_hostname
  type    = "A"
  content = try(local.ui_vm.public_ip, null)
  ttl     = var.cloudflare_dns_ttl
  proxied = var.cloudflare_dns_proxied
  comment = "OilScope UI; managed by Terraform"

  lifecycle {
    precondition {
      condition     = local.ui_hostname != null && trimspace(local.ui_hostname) != ""
      error_message = "The UI workload must define public_endpoint.hostname."
    }

    precondition {
      condition = (
        try(local.ui_vm.public_ip, null) != null &&
        can(cidrnetmask("${local.ui_vm.public_ip}/32"))
      )
      error_message = "The UI workload must have a valid public IPv4 address."
    }

    precondition {
      condition     = !var.cloudflare_dns_proxied || var.cloudflare_dns_ttl == 1
      error_message = "A proxied Cloudflare record must use automatic TTL (1)."
    }
  }
}
