variable "resource_prefix" {
  description = "Prefix used for names of database resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "project_id" {
  description = "Project the instance belongs to. Also the only project allowed to connect to it over Private Service Connect."
  type        = string
}

variable "region" {
  description = "Region of the instance and of the endpoint address. Must be the region of the subnet the endpoint sits in."
  type        = string
}

variable "network_id" {
  description = "ID of the VPC the endpoint is reachable from."
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet the endpoint address is allocated in - the database subnet, kept apart from the workloads."
  type        = string
}

variable "settings" {
  description = "The database block of the project configuration."
  type = object({
    engine_version        = string
    storage_gb            = number
    name                  = string
    backup_retention_days = number
    deletion_protection   = bool
  })

  validation {
    condition     = var.settings.backup_retention_days >= 0 && var.settings.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 0 and 35."
  }
}

variable "tier" {
  description = "Cloud SQL machine tier, already resolved from the size label through the cloud profile."
  type        = string
  nullable    = false
}

variable "labels" {
  description = "Labels applied to every resource."
  type        = map(string)
  default     = {}
}
