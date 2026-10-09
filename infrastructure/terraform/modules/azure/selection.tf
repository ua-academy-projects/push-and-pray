# Which nodes, which profile, which tags - decided by code every provider
# shares, so the answer cannot drift between them.
module "selection" {
  source = "../shared/selection"

  config = var.config
  cloud  = local.this_cloud
  # Azure addresses everything through a subscription. A virtual network
  # carries its own range, like an AWS VPC. A vault name is global across all
  # of Azure, so it is written down rather than derived. The network range is
  # also what the bastion advertises and the other clouds route here.
  required_profile_fields = ["subscription_id", "network_cidr", "key_vault_name"]

  # What this provider accepts in each lookup map. Data, not a branch.
  profile_value_patterns = {
    machine_sizes = "^Standard_[A-Z][A-Za-z0-9_]+$"
    disk_types    = "^(Standard|StandardSSD|Premium)_(LRS|ZRS)$"
    images        = "^[^:\\s]+:[^:\\s]+:[^:\\s]+:[^:\\s]+$"
  }
}
