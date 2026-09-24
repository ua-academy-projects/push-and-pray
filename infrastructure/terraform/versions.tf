terraform {
  required_version = "~> 1.15.1"

  backend "gcs" {}

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.62"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    google = {
      source  = "hashicorp/google"
      version = "~> 7.44.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.24"
    }
  }
}
