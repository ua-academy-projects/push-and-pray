# Which VMs, which profile, which tags - decided by code both providers
# share, so the answer cannot drift between them.
module "selection" {
  source = "../shared/selection"

  config = var.config
  cloud  = local.this_cloud
  # An AWS VPC carries its own range; a GCP network has none.
  required_profile_fields = ["network_cidr"]
}
