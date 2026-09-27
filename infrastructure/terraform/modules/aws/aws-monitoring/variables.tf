variable "instances" {
  description = "AWS EC2 instances that must be monitored."
  type = map(object({
    name        = string
    instance_id = string
  }))
}

variable "notification_email" {
  description = "Email address subscription  to AWS infrastructure alerts."
  type        = string
  nullable    = false
  default     = ""
}

variable "name_prefix" {
  description = "Prefix used for AWS monitoring names"
  type        = string
  nullable    = false
}
