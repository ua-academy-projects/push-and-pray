variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "management_subnet_ids" {
  description = "Management subnet IDs keyed by abstract location."
  type        = map(string)
}

variable "workload_subnet_ids" {
  description = "Workload subnet IDs keyed by abstract location."
  type        = map(string)
}

variable "network_tags_by_location" {
  description = "GCP network tags keyed by abstract location and VM role."
  type        = map(map(string))
}
