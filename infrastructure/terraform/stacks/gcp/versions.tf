terraform {
  required_version = "~> 1.15.1"
  backend "local" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.44.0"
    }
  }
}
