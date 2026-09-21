provider "google" {
  project = try(local.config.clouds.gcp.project_id, null)
  region  = local.config.region_map[local.config.region]["gcp"].region
  zone    = local.config.region_map[local.config.region]["gcp"].zone
}

provider "aws" {
  region = local.config.region_map[local.config.region]["aws"].region
}

# Credentials come from CLOUDFLARE_API_TOKEN, never from the project
# configuration. With cloudflare.enabled = false nothing here is configured,
# so a deployment that manages its DNS by hand needs no token at all.
provider "cloudflare" {}