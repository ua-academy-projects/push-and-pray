variable "resource_prefix" {
  description = "Prefix shared by every resource name."
  type        = string
}

variable "email" {
  description = "Address every alert and budget notification goes to. SNS asks it to confirm the subscription first."
  type        = string
}

variable "metrics" {
  description = "The monitoring module's metric table: one alarm per instance and entry."
  type = map(object({
    title      = string
    namespace  = string
    name       = string
    stat       = string
    dimension  = string
    threshold  = number
    comparison = string
    missing    = string
  }))
}

variable "instances" {
  description = "Every instance to watch, keyed by name."
  type = map(object({
    id        = string
    volume_id = string
    role      = string
    name      = string
  }))
}

variable "budget_usd" {
  description = "Monthly spend above which the billing alert fires. Null creates no budget."
  type        = number
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
