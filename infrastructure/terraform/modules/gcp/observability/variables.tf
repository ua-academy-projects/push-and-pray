variable "project_id" { type = string }
variable "resource_prefix" { type = string }
variable "alert_email" { type = string }
variable "synthetic_url" { type = string }

variable "database_instance_id" {
  type    = string
  default = null
}

variable "instances" {
  type = map(object({
    instance_id = string
    zone        = string
  }))
}
