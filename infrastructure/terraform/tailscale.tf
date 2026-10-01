locals {
  tailscale_config        = lookup(local.config, "tailscale", {})
  tailscale_enabled       = lookup(local.tailscale_config, "enabled", false)
  tailscale_manage_policy = lookup(local.tailscale_config, "manage_policy", false)
  tailscale_subnet_cidrs = [
    for cloud in ["gcp", "aws", "azure"] : local.config.network[cloud].vpc_cidr
  ]
}

# A tagged, reusable key lets Ansible register all three long-lived bastions
# without browser login. `key` is sensitive, but it is still stored in state;
# use an encrypted remote backend with tightly restricted access.
resource "tailscale_tailnet_key" "subnet_router" {
  count = local.tailscale_enabled ? 1 : 0

  # A tagged key is rejected until the policy has declared the tag owner.
  # Without this explicit edge Terraform may create the ACL and key in parallel.
  depends_on = [tailscale_acl.multicloud]

  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 7776000
  description   = "oilscope-multicloud-subnet-router"
  tags          = ["tag:subnet-router"]
}

# This resource owns the ENTIRE tailnet policy. It is deliberately opt-in so
# an existing policy is never overwritten by an ordinary infrastructure apply.
resource "tailscale_acl" "multicloud" {
  count = local.tailscale_enabled && local.tailscale_manage_policy ? 1 : 0

  acl = jsonencode({
    tagOwners = {
      "tag:subnet-router" = ["autogroup:admin"]
    }
    autoApprovers = {
      routes = {
        for cidr in local.tailscale_subnet_cidrs : cidr => ["tag:subnet-router"]
      }
    }
    grants = [
      # Preserve the default policy that was imported from a fresh tailnet.
      # Replace this with least-privilege grants once normal user/device access
      # has been modelled in Terraform.
      {
        src = ["*"]
        dst = ["*"]
        ip  = ["*"]
      },
      {
        src = concat(["tag:subnet-router"], local.tailscale_subnet_cidrs)
        dst = local.tailscale_subnet_cidrs
        ip  = ["*"]
      }
    ]
    ssh = [{
      action = "check"
      src    = ["autogroup:member"]
      dst    = ["autogroup:self"]
      users  = ["autogroup:nonroot", "root"]
    }]
  })

  # An operator must consciously opt in on a fresh tailnet. For an existing
  # one, import its policy first rather than silently replacing it.
  overwrite_existing_content = false
  reset_acl_on_destroy       = false
}
