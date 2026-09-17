provider "google" {
  project = lookup(
    lookup(local.config.clouds, "gcp", {}),
    "project_id",
    null
  )

  region = lookup(
    lookup(lookup(local.config.clouds, "gcp", {}), "regions", {}),
    local.config.location.region,
    null
  )

  zone = lookup(
    lookup(lookup(local.config.clouds, "gcp", {}), "zones", {}),
    local.config.location.zone,
    null
  )
}

provider "aws" {
  region = lookup(
    lookup(lookup(local.config.clouds, "aws", {}), "regions", {}),
    local.config.location.region,
    null
  )
}

provider "cloudflare" {
  api_token = try(local.config.cloudflare.api_token, null)
}
