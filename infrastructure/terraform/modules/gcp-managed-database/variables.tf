variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "network_id" {
  description = "GCP VPC used for private Cloud SQL connectivity."
  type        = string
}

variable "client_service_accounts" {
  description = "Service accounts allowed to connect through the Cloud SQL Auth Proxy."
  type        = set(string)
}

variable "password" {
  description = "Initial PostgreSQL application password."
  type        = string
  sensitive   = true
  ephemeral   = true
}
