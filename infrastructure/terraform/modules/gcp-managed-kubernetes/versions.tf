terraform {
  required_version = "~> 1.16.3"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.3.0"
    }
  }
}
