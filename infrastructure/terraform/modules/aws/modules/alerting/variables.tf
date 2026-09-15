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
  description = "Every instance to watch, keyed by name, with the role that says which containers run on it."
  type = map(object({
    id        = string
    volume_id = string
    role      = string
    name      = string
  }))
}

variable "containers_by_role" {
  description = "Container names each role runs. CloudWatch cannot lift a name out of a log line into a notification, so the pairs are enumerated and each gets its own alarm, named after both."
  type        = map(list(string))
  default = {
    infra   = ["petroscope-postgres-1", "petroscope-migrate-1", "petroscope-rabbitmq-1", "petroscope-redis-1"]
    history = ["petroscope-history-1"]
    fetcher = ["petroscope-fetcher-1"]
    ui      = ["petroscope-ui-1", "oilscope-proxy-traefik-1"]
  }
}

variable "log_group_name" {
  description = "Log group the journals land in; the container and HTTP alarms filter it."
  type        = string
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
