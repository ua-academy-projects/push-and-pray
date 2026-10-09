resource "tailscale_acl" "oilscope" {
  count = local.tailscale_enabled && local.tailscale_manage_policy ? 1 : 0

  overwrite_existing_content = true
  reset_acl_on_destroy       = false
  acl = jsonencode({
    tagOwners = {
      (local.tailscale_tag) = ["autogroup:admin"]
    }
    grants = [
      {
        src = ["autogroup:member", local.tailscale_tag]
        dst = concat([local.tailscale_tag], local.tailscale_advertised_routes)
        ip  = ["*"]
      }
    ]
    autoApprovers = {
      routes = {
        for route in local.tailscale_advertised_routes : route => [local.tailscale_tag]
      }
    }
  })
}

resource "tailscale_tailnet_key" "bootstrap" {
  count = local.tailscale_enabled ? 1 : 0

  reusable            = true
  ephemeral           = false
  preauthorized       = true
  expiry              = local.tailscale_key_expiry
  recreate_if_invalid = "always"
  tags                = [local.tailscale_tag]
  description         = "OilScopeTerraformCloudInitBootstrap"

  depends_on = [tailscale_acl.oilscope]
}

module "cloud_init" {
  source  = "tailscale/tailscale/cloudinit"
  version = "0.0.12"

  for_each = local.tailscale_enabled ? local.tailscale_hostnames : {}

  auth_key         = tailscale_tailnet_key.bootstrap[0].key
  hostname         = each.value
  accept_routes    = true
  advertise_tags   = [local.tailscale_tag]
  advertise_routes = lookup(local.tailscale_vm_advertised_routes, each.key, [])
  base64_encode    = false
  gzip             = false
  timeout          = "180s"
}

check "tailscale_has_one_global_bastion" {
  assert {
    condition = !local.tailscale_enabled || length([
      for vm in values(local.tailscale_vms) : vm if vm.role == "bastion"
    ]) == 1
    error_message = "Tailscale mode requires exactly one global administrative bastion."
  }
}

check "tailscale_has_router_in_every_workload_cloud" {
  assert {
    condition = !local.tailscale_enabled || alltrue([
      for cloud in local.tailscale_active_clouds :
      try(local.tailscale_router_by_cloud[cloud], null) != null
    ])
    error_message = "Every cloud containing workloads must contain at least one K3s server for subnet routing."
  }
}

check "tailscale_tag_is_valid" {
  assert {
    condition     = can(regex("^tag:[a-zA-Z0-9-]+$", local.tailscale_tag))
    error_message = "The Tailscale tag must use tag:name syntax."
  }
}

check "tailscale_key_expiry_is_valid" {
  assert {
    condition     = local.tailscale_key_expiry >= 300 && local.tailscale_key_expiry <= 7776000
    error_message = "The Tailscale auth-key expiry must be between 300 and 7776000 seconds."
  }
}
