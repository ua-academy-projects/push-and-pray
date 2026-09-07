variable "name" {
  description = "Name used for the service account. Matches the VM it belongs to."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.name))
    error_message = "name must be 6 to 30 characters, start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "description" {
  description = "What this identity is for, shown in the console."
  type        = string
  default     = ""
}
