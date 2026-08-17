variable "project_id" {
  description = "Google Cloud project ID"
  type        = string

  validation {
    condition     = length(var.project_id) >= 6 && length(var.project_id) <= 30
    error_message = "project_id must contain between 6 and 30 characters."
  }
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "europe-central2"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid GCP region, for example europe-central2."
  }
}

variable "zone" {
  description = "Google Cloud zone"
  type        = string
  default     = "europe-central2-a"

  validation {
    condition     = startswith(var.zone, "${var.region}-")
    error_message = "zone must belong to the selected region."
  }
}

variable "name_prefix" {
  description = "Prefix used for GCP resource names"
  type        = string
  default     = "oil"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "name_prefix must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "common_labels" {
  description = "Additional labels applied to managed GCP resources"
  type        = map(string)
  default     = {}
}
