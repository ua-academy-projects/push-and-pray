variable "config" {
  type = any
}

variable "azure_secret_version_managers" {
  type    = list(string)
  default = []
}