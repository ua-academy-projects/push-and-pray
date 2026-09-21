terraform {
  required_version = "~> 1.15.1"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.44.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.63"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.12"
    }
  }
}
