# Which nodes, which profile, which tags - decided by code both providers
# share, so the answer cannot drift between them.
module "selection" {
  source = "../shared/selection"

  config = var.config
  cloud  = local.this_cloud
  # An AWS VPC carries its own range, which is also what the bastion
  # advertises and the other clouds route here.
  required_profile_fields = ["network_cidr"]

  # What this provider accepts in each lookup map. Data, not a branch.
  profile_value_patterns = {
    machine_sizes = "^[a-z][0-9][a-z]*\\.[a-z0-9]+$"
    disk_types    = "^(standard|gp2|gp3|io1|io2)$"
    images        = "^ami-[0-9a-f]{8,17}$"
  }
}
