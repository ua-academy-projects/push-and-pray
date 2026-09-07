variable "name" {
  description = "Name used for the IAM role and its instance profile. Matches the VM it belongs to."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "description" {
  description = "What this identity is for, shown in the console."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to the role and the instance profile."
  type        = map(string)
}
