variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "networks" {
  description = "GCP network identifiers keyed by logical location."
  type = map(object({
    network_id = string
  }))
}
