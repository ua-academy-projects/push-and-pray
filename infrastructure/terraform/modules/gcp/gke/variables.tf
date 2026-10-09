variable "config" {
  type = any
}

variable "enabled" {
  type = bool
}

variable "network_id" {
  type = string
}

variable "workload_subnet_id" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "network_tags" {
  type = map(string)
}

variable "authorized_cidrs" {
  description = "CIDRs allowed to reach the public GKE control plane endpoint."
  type        = list(string)
}
