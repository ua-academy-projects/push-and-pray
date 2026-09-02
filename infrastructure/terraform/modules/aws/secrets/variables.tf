variable "tags" {
  description = "Tags applied to AWS Secrets Manager containers."
  type        = map(string)
}

variable "workload_secret_access" {
  description = "Secret IDs each AWS workload may read, keyed by logical VM name."
  type        = map(list(string))
}

variable "iam_role_names" {
  description = "AWS IAM role names keyed by logical VM name."
  type        = map(string)
}
