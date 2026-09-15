variable "project_id" {
  description = "Project whose IAM grants the metric writers and which owns the dashboard."
  type        = string
}

variable "resource_prefix" {
  description = "Prefix shared by every resource name."
  type        = string
}

variable "identities" {
  description = "IAM member string of every VM identity that ships metrics, keyed by VM name."
  type        = map(string)
}

variable "labels" {
  description = "Labels every VM carries. application and environment select this environment's VMs, so nothing has to list them."
  type        = map(string)
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
