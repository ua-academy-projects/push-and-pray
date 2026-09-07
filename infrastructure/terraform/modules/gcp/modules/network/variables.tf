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
    })
  })

  validation {
    condition = alltrue([
      for cidr in values(var.profile.subnets) :
      can(cidrhost(cidr, 0))
    ])
    error_message = "Every subnet range must be a valid CIDR."
  }
}
