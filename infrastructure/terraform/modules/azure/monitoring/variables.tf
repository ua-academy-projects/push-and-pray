variable "resource_group_name" { type = string }
variable "resource_group_id" { type = string }
variable "location" { type = string }
variable "resource_prefix" { type = string }
variable "tags" { type = map(string) }
variable "settings" {
  type = object({
    notification_email = string
    cpu                = object({ threshold_percent = number, duration_seconds = number })
    disk               = object({ threshold_percent = number, duration_seconds = number })
    uptime             = object({ enabled = bool, path = string, period_seconds = number, timeout_seconds = number })
    logs               = object({ enabled = bool, error_pattern = string })
    budget             = object({ enabled = bool, amount = number, currency = string, thresholds = list(number) })
  })
}
variable "virtual_machine_ids" { type = map(string) }
variable "uptime_hostname" {
  type     = string
  default  = null
  nullable = true
}
