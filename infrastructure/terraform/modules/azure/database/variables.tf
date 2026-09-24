variable "config" {
  description = "Full parsed project configuration."
  type        = any
}

variable "network" {
  description = "Outputs from the Azure network module; postgres is null outside cloud database mode."
  type        = any
}

variable "vault" {
  description = "Outputs of the azure_secrets module: the vault the administrator credential is written into."
  type        = any
}
