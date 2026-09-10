variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "network_id" {
  type = string
}

variable "resource_prefix" {
  type = string
}

variable "labels" {
  type = map(string)
}

variable "database" {
  type = object({
    name = string
    user = string
    port = number
  })
}

variable "managed_settings" {
  description = "GCP-specific Cloud SQL engine and compute settings."
  type = object({
    database_version = string
    tier             = string
  })
}

variable "managed_database_password" {
  description = "Password passed to Cloud SQL through a write-only provider argument."
  type        = string
  sensitive   = true
  nullable    = true
}

variable "managed_database_password_version" {
  description = "Non-secret version that triggers a Cloud SQL password update after rotation."
  type        = number
}
