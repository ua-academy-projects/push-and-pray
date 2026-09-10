terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = ">= 6.63.0, < 7.0.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.7" }
  }
}
