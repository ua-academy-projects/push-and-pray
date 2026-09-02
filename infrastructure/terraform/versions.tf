terraform {
  required_version = "~> 1.15.1"

  backend "gcs" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    google = {
      source  = "hashicorp/google"
      version = "~> 7.44.0"
    }
  }
}
