variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "networks" {
  description = "AWS network identifiers keyed by logical location."
  type = map(object({
    region = string
    vpc_id = string
  }))
}
