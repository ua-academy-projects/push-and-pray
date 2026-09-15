variable "resource_prefix" {
  description = "Prefix shared by every resource name."
  type        = string
}

variable "region" {
  description = "Region the dashboard reads metrics from."
  type        = string
}

variable "identities" {
  description = "IAM role name of every instance identity that ships metrics, keyed by instance name."
  type        = map(string)
}

variable "instances" {
  description = "Every instance to watch, keyed by name. CloudWatch addresses a series by instance or volume ID, so unlike GCP there is no label to select them by."
  type = map(object({
    id        = string
    volume_id = string
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
