variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "project_services" {
  description = "GCP project services enabled before VM creation."
  type        = list(string)
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
