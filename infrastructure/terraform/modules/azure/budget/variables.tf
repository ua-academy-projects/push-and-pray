variable "name" { type = string }
variable "settings" {
  type = object({
    enabled           = optional(bool, false)
    monthly_amount    = optional(number, 100)
    currency          = optional(string, "USD")
    actual_thresholds = optional(set(number), [50, 100])
    email_recipients  = optional(set(string), [])
    start_date        = optional(string, "")
  })
  default = {}
}
variable "resource_group_id" {
  type    = string
  default = null
}
