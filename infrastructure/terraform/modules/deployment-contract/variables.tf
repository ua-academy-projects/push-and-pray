variable "project_config_path" {
  description = "Path to the shared project configuration JSON."
  type        = string
}

variable "provider_name" {
  description = "Provider implemented by the calling isolated stack."
  type        = string
}

variable "nodes" {
  description = "Normalized provider node records."
  type        = any
}

variable "managed_database" {
  description = "Managed database connection metadata, or null for portable mode."
  type        = any
  default     = null
}

variable "managed_service_images" {
  description = "Mirrored RabbitMQ and Redis image records, or null for portable mode."
  type        = any
  default     = null
}

variable "monitoring" {
  description = "Normalized monitoring identifiers."
  type        = any
}

variable "dns" {
  description = "Normalized public DNS record."
  type        = any
}
