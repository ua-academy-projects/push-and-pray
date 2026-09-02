variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "iam_role_names" {
  description = "AWS IAM role names keyed by logical VM name."
  type        = map(string)
}
