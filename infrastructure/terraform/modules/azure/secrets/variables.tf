variable "config" {
  description = "Full parsed project configuration (see project_config_path in the root module)."
  type        = any
}

variable "network" {
  description = "Outputs of the azure_network module; the vault lives in the same resource group and location."
  type = object({
    resource_group_name = string
    location            = string
  })
}

variable "vms" {
  description = "Outputs of the azure_vm module, keyed by name."
  type = map(object({
    identity_principal_id = string
  }))
}

variable "secret_version_managers" {
  description = "Entra object IDs allowed to write new versions of every secret. Key Vault has no add-version-only role, so this grants Key Vault Secrets Officer at the vault: use it for the deployment controller, never for a workload identity."
  type        = list(string)
  default     = []
}
