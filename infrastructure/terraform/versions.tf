terraform {
  required_version = "~> 1.15.1"

  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.44.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.62.0"
    }
  }
}
