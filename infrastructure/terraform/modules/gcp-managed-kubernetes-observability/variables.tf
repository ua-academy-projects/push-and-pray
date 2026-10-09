variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "cluster" {
  description = "GKE cluster identity used to scope Cloud Monitoring queries."
  type = object({
    name     = string
    location = string
  })
}
