variable "project_id" { type = string }
variable "resource_prefix" { type = string }
variable "alert_email" { type = string }
variable "synthetic_url" { type = string }
variable "http_5xx_threshold" { type = number }
variable "http_5xx_window_seconds" { type = number }

variable "database_instance_id" {
  type    = string
  default = null
}

variable "database_enabled" {
  type    = bool
  default = false
}

variable "instances" {
  type = map(object({
    instance_id = string
    zone        = string
  }))
}
