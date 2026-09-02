variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "project_services" {
  description = "GCP project services enabled before network creation."
  type        = list(string)
}
