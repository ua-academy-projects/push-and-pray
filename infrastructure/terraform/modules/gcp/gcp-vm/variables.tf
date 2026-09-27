variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}
variable "subnet_ids" {
  description = "Management and workload subnet IDs."
  type        = map(string)
}
variable "service_account_emails" {
  description = "Runtime service accounts keyed by VM name."
  type        = map(string)
}

variable "database_runtime" {
  description = "Non-secret database and queue connection metadata exposed to Ansible through instance metadata."
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
