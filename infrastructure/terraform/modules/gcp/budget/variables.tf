variable "name" { type = string }
variable "settings" {
  type = object({
    enabled        = optional(bool, false)
    monthly_amount = optional(number, 100)
    currency       = optional(string, "USD")
    # Absolute currency amounts (e.g. 50 means "notify at $50 actual spend"),
    # not fractions of monthly_amount; converted to GCP's required
    # threshold_percent internally.
    actual_thresholds  = optional(set(number), [50, 100])
    email_recipients   = optional(set(string), [])
    billing_account_id = optional(string, "")
  })
  default = {}
  validation {
    condition     = var.settings.monthly_amount > 0 && floor(var.settings.monthly_amount) == var.settings.monthly_amount && length(var.settings.actual_thresholds) > 0 && length(var.settings.actual_thresholds) <= 5 && alltrue([for n in var.settings.actual_thresholds : n > 0])
    error_message = "Budget amount must be positive whole currency units; provide 1–5 positive threshold amounts."
  }
  validation {
    condition     = !var.settings.enabled || (length(var.settings.email_recipients) > 0 && length(var.settings.email_recipients) <= 5)
    error_message = "An enabled budget requires supported email recipients."
  }
  validation {
    condition     = can(regex("^[A-Z]{3}$", var.settings.currency)) && alltrue([for email in var.settings.email_recipients : can(regex("^[^ @]+@[^ @]+\\.[^ @]+$", email))])
    error_message = "Provide an ISO currency code and valid email recipients."
  }
}
variable "project_id" {
  type    = string
  default = null
  validation {
    condition     = !var.settings.enabled || (try(length(var.project_id) > 0, false) && length(var.settings.billing_account_id) > 0)
    error_message = "GCP budgets require a project and billing account."
  }
}
