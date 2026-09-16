variable "resource_prefix" {
  description = "Prefix used for human-readable CloudWatch and SNS resource names."
  type        = string
}

variable "tags" {
  description = "Tags shared by monitoring resources."
  type        = map(string)
}

variable "settings" {
  description = "Provider-neutral monitoring configuration resolved by the AWS wrapper."
  type = object({
    notification_email = string
    cpu                = object({ threshold_percent = number, duration_seconds = number })
    disk               = object({ threshold_percent = number, duration_seconds = number })
    uptime             = object({ enabled = bool, path = string, period_seconds = number, timeout_seconds = number })
    logs               = object({ enabled = bool, error_pattern = string })
    budget             = object({ enabled = bool, amount = number, currency = string, thresholds = list(number) })
  })
}

variable "instance_ids" {
  description = "EC2 instance IDs keyed by logical VM name."
  type        = map(string)
}

variable "managed_database_enabled" {
  description = "Whether a managed RDS database is configured."
  type        = bool
  default     = false
}

variable "database_instance_identifier" {
  description = "Private RDS DB instance identifier to monitor."
  type        = string
  default     = null
  nullable    = true
}

variable "uptime_hostname" {
  description = "Public UI hostname monitored by a Route 53 HTTPS health check."
  type        = string
  default     = null
  nullable    = true
}
