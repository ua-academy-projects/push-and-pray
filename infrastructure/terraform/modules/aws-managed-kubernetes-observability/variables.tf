variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "cluster" {
  description = "EKS cluster identity used to scope Container Insights."
  type = object({
    name     = string
    location = string
  })
}
