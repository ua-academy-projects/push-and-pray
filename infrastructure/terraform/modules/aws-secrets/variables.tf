variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}

variable "generated_secret_ids" {
  description = "Secret IDs whose initial values Terraform should generate."
  type        = list(string)
  default     = []
}
