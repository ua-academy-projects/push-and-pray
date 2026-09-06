# Which VMs, which profile, which labels - decided by code both providers
# share, so the answer cannot drift between them.
module "selection" {
  source = "../shared/selection"

  config                  = var.config
  cloud                   = local.this_cloud
  required_profile_fields = ["project_id"]
}
