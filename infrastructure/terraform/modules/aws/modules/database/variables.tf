variable "resource_prefix" {
  description = "Prefix used for names of database resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "vpc_id" {
  description = "ID of the VPC the instance's security group belongs to."
  type        = string
}

variable "subnet_ids" {
  description = "IDs of the database subnets. RDS needs two, in different availability zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "A DB subnet group must span two availability zones, so at least two subnet IDs are needed."
  }
}

variable "client_security_group_ids" {
  description = "Security groups allowed to reach the database on its port, keyed by the scope name the rule is described with."
  type        = map(string)
}

variable "settings" {
  description = "The database block of the project configuration."
  type = object({
    engine_version        = string
    storage_gb            = number
    name                  = string
    username              = string
    backup_retention_days = number
    deletion_protection   = bool
  })

  validation {
    condition     = var.settings.backup_retention_days >= 0 && var.settings.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 0 and 35."
  }
}

variable "instance_class" {
  description = "RDS instance class, already resolved from the size label through the cloud profile."
  type        = string
  nullable    = false
}

variable "port" {
  description = "Port PostgreSQL listens on."
  type        = number
  default     = 5432
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
