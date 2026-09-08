variable "project_id" {
  description = "GCP project that owns the observability resources."
  type        = string
}

variable "billing_account_id" {
  description = "Billing account ID used only when the budget is enabled."
  type        = string
  default     = null
  nullable    = true
}

variable "resource_prefix" {
  description = "Prefix used for human-readable observability resource names."
  type        = string
}

variable "labels" {
  description = "Labels shared by monitoring resources."
  type        = map(string)
}

variable "uptime_hostname" {
  description = "Public UI hostname checked over HTTPS."
  type        = string
  nullable    = true
}

variable "service_account_emails" {
  description = "VM service-account emails keyed by logical VM name."
  type        = map(string)
}

variable "settings" {
  description = "Provider-neutral monitoring thresholds and feature switches resolved by the GCP wrapper."
  type = object({
    notification_email = string
    cpu = object({
      threshold_percent = number
      duration_seconds  = number
    })
    disk = object({
      threshold_percent = number
      duration_seconds  = number
    })
    uptime = object({
      enabled         = bool
      path            = string
      period_seconds  = number
      timeout_seconds = number
    })
    logs = object({
      enabled       = bool
      error_pattern = string
    })
    budget = object({
      enabled    = bool
      amount     = number
      currency   = string
      thresholds = list(number)
    })
  })

  validation {
    condition = (
      var.settings.cpu.threshold_percent > 0 &&
      var.settings.cpu.threshold_percent <= 100 &&
      var.settings.disk.threshold_percent > 0 &&
      var.settings.disk.threshold_percent <= 100
    )
    error_message = "CPU and disk thresholds must be percentages greater than 0 and at most 100."
  }

  validation {
    condition = (
      var.settings.cpu.duration_seconds % 60 == 0 &&
      var.settings.disk.duration_seconds % 60 == 0 &&
      contains([60, 300, 600, 900], var.settings.uptime.period_seconds) &&
      var.settings.uptime.timeout_seconds >= 1 &&
      var.settings.uptime.timeout_seconds <= 60
    )
    error_message = "Alert durations must be minute multiples; uptime period must be 60, 300, 600, or 900 seconds and timeout must be 1-60 seconds."
  }

  validation {
    condition = (
      !var.settings.budget.enabled ||
      (
        var.settings.budget.amount > 0 &&
        alltrue([for threshold in var.settings.budget.thresholds : threshold > 0])
      )
    )
    error_message = "An enabled budget needs a positive amount and positive 1.0-based thresholds."
  }
}
