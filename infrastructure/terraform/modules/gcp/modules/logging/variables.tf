variable "project_id" {
  description = "Project whose log bucket holds the journals and whose IAM grants the writers."
  type        = string
}

variable "identities" {
  description = "IAM member string of every VM identity that ships logs, keyed by VM name."
  type        = map(string)
}

variable "retention_days" {
  description = "How long the _Default bucket keeps an entry."
  type        = number
  default     = 30
}
