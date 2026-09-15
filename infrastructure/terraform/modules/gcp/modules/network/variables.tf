variable "resource_prefix" {
  description = "Prefix used for names of network resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "resource_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "profile" {
  description = "This cloud's profile. Only the subnet ranges are read; a GCP network carries no range of its own."
  type = object({
    subnets = object({
      management = string
      workload   = string
      database   = optional(list(string), [])
    })
  })

  validation {
    condition = alltrue([
      for cidr in concat(
        [var.profile.subnets.management, var.profile.subnets.workload],
        var.profile.subnets.database,
      ) :
      can(cidrhost(cidr, 0))
    ])
    error_message = "Every subnet range must be a valid CIDR."
  }
}

variable "enable_database_subnet" {
  description = "Whether to create the database subnet. Only a managed database lives there; a self-hosted one sits on a workload VM."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_database_subnet || length(var.profile.subnets.database) > 0
    error_message = "The database subnet needs a range in subnets.database."
  }
}
