variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}

variable "enable_managed_database" {
  description = "Enable the APIs needed by private Cloud SQL."
  type        = bool
  default     = false
}
