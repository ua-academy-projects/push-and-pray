provider "google" {
  project = try(local.config.project_id, null)
  region  = local.config.regions[local.config.region].gcp.region
  zone    = local.config.regions[local.config.region].gcp.zone
}
provider "aws" {
  region = local.config.regions[local.config.region].aws.region
}
provider "cloudflare" {
  api_token = coalesce(var.cloudflare_api_token, "0000000000000000000000000000000000000000")
}