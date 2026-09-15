variable "project_id" {
  description = "Project the alert policies, the notification channel and the budget filter belong to."
  type        = string
}

variable "resource_prefix" {
  description = "Prefix shared by every resource name."
  type        = string
}

variable "email" {
  description = "Address every alert and budget notification goes to."
  type        = string
}

variable "metrics" {
  description = "The monitoring module's metric table: one alert policy per entry. A null threshold alerts when the series disappears, which is what a stopped VM looks like."
  type = map(object({
    title     = string
    filter    = string
    aligner   = string
    threshold = number
  }))
}

variable "log_name" {
  description = "Log the agents write the journal to; the container and HTTP alerts match entries in it."
  type        = string
}

variable "budget_usd" {
  description = "Monthly spend above which the billing alert fires. Null creates no budget."
  type        = number
  default     = null
}

variable "billing_account" {
  description = "Billing account the budget is created on. Null creates no budget."
  type        = string
  default     = null
}
