variable "config" {
  description = "Project configuration decoded from JSON."
  type        = any
  nullable    = false
}

variable "network_id" {
  description = "VPC network connected to Cloud SQL through Private Services Access."
  type        = string
}

variable "password_secret_id" {
  description = "ID of the existing Secret Manager secret for the database password."
  type        = string
}
