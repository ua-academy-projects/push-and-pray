variable "resource_prefix" {
  description = "Prefix used for human-readable CloudWatch and SNS resource names."
  type        = string
}

variable "tags" {
  description = "Tags shared by monitoring resources."
  type        = map(string)
}

variable "notification_email" {
  description = "Email address subscribed to CloudWatch alarm notifications."
  type        = string
}

variable "cpu" {
  description = "CPU threshold and the continuous duration that must breach it."
  type = object({
    threshold_percent = number
    duration_seconds  = number
  })

  validation {
    condition = (
      var.cpu.threshold_percent > 0 &&
      var.cpu.threshold_percent <= 100 &&
      var.cpu.duration_seconds >= 60 &&
      var.cpu.duration_seconds % 60 == 0
    )
    error_message = "The CPU threshold must be from 0 to 100 and duration must be a whole number of minutes."
  }
}

variable "instance_ids" {
  description = "EC2 instance IDs keyed by logical VM name."
  type        = map(string)
}
