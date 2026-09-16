variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "network" {
  description = "AWS network containing the managed database."
  type        = any
}

variable "client_security_group_ids" {
  description = "Security groups permitted to connect to PostgreSQL, keyed by workload."
  type        = map(string)
}

variable "password" {
  description = "Initial PostgreSQL application password."
  type        = string
  sensitive   = true
  ephemeral   = true
}
