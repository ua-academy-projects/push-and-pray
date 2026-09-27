variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}
variable "subnet_ids" {
  description = "Management and workload subnet IDs."
  type        = map(string)
}
variable "security_group_ids" {
  description = "Security group IDs keyed by VM name."
  type        = map(string)
}
variable "instance_profile_name" {
  description = "IAM profile for EC2."
  type        = string
  default     = null
}

variable "database_runtime" {
  description = "Non-secret database and queue connection metadata exposed to Ansible through EC2 tags."
  type = object({
    mode                   = string
    cloud                  = string
    host                   = string
    port                   = number
    name                   = string
    username               = string
    sslmode                = string
    secret_reference       = string
    queue_backend          = string
    queue_host             = string
    queue_port             = number
    queue_username         = string
    queue_vhost            = string
    queue_secret_reference = string
  })
}
