variable "resource_prefix" {
  description = "Prefix shared by every resource name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the dashboard is created in."
  type        = string
}

variable "location" {
  description = "Azure region of the dashboard."
  type        = string
}

variable "instances" {
  description = "Every VM to chart, keyed by name. Platform metrics are addressed by resource ID, so as on AWS there is no label to select them by."
  type = map(object({
    id   = string
    name = string
  }))
}

variable "thresholds" {
  description = "Where each alert fires. Every attribute is optional and has the project's agreed default."
  type = object({
    cpu_utilization                  = optional(number, 0.75)
    memory_used_gb                   = optional(number, 1.5)
    disk_write_ops_per_second        = optional(number, 1000)
    network_received_mbit_per_second = optional(number, 1)
  })
  default = {}
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
