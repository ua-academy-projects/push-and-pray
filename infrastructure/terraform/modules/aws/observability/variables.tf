variable "resource_prefix" { type = string }
variable "region" { type = string }
variable "alert_email" { type = string }
variable "monthly_budget_usd" { type = number }
variable "synthetic_url" { type = string }
variable "log_retention_days" { type = number }
variable "tags" { type = map(string) }

variable "database_identifier" {
  type    = string
  default = null
}

variable "instances" {
  type = map(object({
    instance_id    = string
    iam_role_name  = string
    root_volume_id = string
  }))
}
