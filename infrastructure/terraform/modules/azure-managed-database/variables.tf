variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "network" {
  description = "Azure virtual network containing the managed database."
  type        = any
}

variable "resource_group_name" {
  description = "Azure resource group for the managed database."
  type        = string
}

variable "password" {
  description = "Initial PostgreSQL application password."
  type        = string
  sensitive   = true
  ephemeral   = true
}
