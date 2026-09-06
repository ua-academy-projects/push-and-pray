# Which VMs, which profile, which labels - decided by code both providers
# share, so the answer cannot drift between them.
module "selection" {
  source = "../shared/selection"

  config                  = var.config
  cloud                   = local.this_cloud
  required_profile_fields = ["project_id"]

  # What this provider accepts in each lookup map. Data, not a branch.
  profile_value_patterns = {
    machine_sizes = "^[a-z][0-9]?[a-z0-9]*-[a-z0-9-]+$"
    disk_types    = "^pd-(standard|balanced|ssd)$"
    images        = "^projects/[^/]+/global/images/"
  }
}
