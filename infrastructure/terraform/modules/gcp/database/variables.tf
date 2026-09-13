variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "network_id" {
  description = "VPC with Private Services Access for Cloud SQL."
  type        = string
  nullable    = true
}

variable "private_service_connection" {
  description = "Private Services Access connection dependency."
  type        = string
  nullable    = true
}
