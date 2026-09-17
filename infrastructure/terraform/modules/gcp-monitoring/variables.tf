variable "instances" {
  description = "GCP Compute Engine instances that must be monitored."
  type = map(object({
    name        = string
    instance_id = string
  }))

  nullable = false

  validation {
    condition = alltrue([
      for instance in values(var.instances) :
      trimspace(instance.name) != "" &&
      trimspace(instance.instance_id) != ""
    ])

    error_message = "Every GCP instance must have a non-empty name and instance_id."
  }
}

variable "instance_keys" {
  description = "Configuration keys of GCP instances; these keys are known before apply."
  type        = set(string)
  nullable    = false
}

variable "notification_email" {
  description = "Email address used for GCP infrastructure alerts."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.notification_email) != ""
    error_message = "notification_email must not be empty."
  }
}

variable "name_prefix" {
  description = "Prefix used for GCP monitoring resource names."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.name_prefix) != ""
    error_message = "name_prefix must not be empty."
  }
}
