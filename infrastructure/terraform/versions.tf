terraform {
  required_version = "~> 1.16.3"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.64.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.25.0"
    }
  }
}
