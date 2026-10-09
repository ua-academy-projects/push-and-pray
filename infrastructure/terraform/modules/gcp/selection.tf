# Which nodes, which profile, which labels - decided by code every provider
# shares, so the answer cannot drift between them.
module "selection" {
  source = "../shared/selection"

  config = var.config
  cloud  = local.this_cloud
  # A GCP network has no range of its own; network_cidr is the summary of its
  # subnets that the bastion advertises and the other clouds route here.
  required_profile_fields = ["project_id", "network_cidr"]

  # What this provider accepts in each lookup map. Data, not a branch.
  profile_value_patterns = {
    machine_sizes = "^[a-z][0-9]?[a-z0-9]*-[a-z0-9-]+$"
    disk_types    = "^pd-(standard|balanced|ssd)$"
    images        = "^projects/[^/]+/global/images/"
  }
}
