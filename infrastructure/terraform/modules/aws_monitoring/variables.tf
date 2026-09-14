variable "resource_prefix" {
  description = "Shared deployment resource name prefix."
  type        = string
}

variable "monitoring" {
  description = "Provider-neutral monitoring configuration."
  type = object({
    enabled            = bool
    notification_email = string
    cpu = object({
      enabled           = bool
      threshold_percent = number
      duration_minutes  = number
    })
    vm_health = optional(object({
      enabled = bool
    }), { enabled = false })
    lifecycle = optional(object({
      enabled       = bool
      notify_states = set(string)
    }), { enabled = false, notify_states = [] })
    http_5xx = optional(object({
      enabled          = bool
      threshold_count  = number
      duration_minutes = number
    }), { enabled = false, threshold_count = 5, duration_minutes = 5 })
  })
}

variable "vms" {
  description = "Terraform-managed AWS VMs keyed by project VM key."
  type = map(object({
    name          = string
    instance_id   = string
    role          = optional(string, "")
    iam_role_name = optional(string, "")
  }))
}

variable "tags" {
  description = "Common tags for monitoring resources."
  type        = map(string)
}
