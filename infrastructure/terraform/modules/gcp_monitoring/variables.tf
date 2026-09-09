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
  })
}

variable "vms" {
  description = "Terraform-managed GCP VMs keyed by project VM key."
  type = map(object({
    name        = string
    instance_id = string
  }))
}
