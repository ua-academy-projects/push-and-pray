variable "project_config_path" {
  description = "Path to the JSON file containing project-specific configuration, relative to this root. The default resolves to the repository root when Terraform is run with -chdir=infrastructure/terraform. The file is never committed."
  type        = string
  nullable    = false
  default     = "../../project-config.new.json"
}

//for Azure
variable "azure_secret_version_managers" {
  description = "Entra object IDs allowed to write new secret versions. Key Vault has no add-version-only role, so this grants Key Vault Secrets Officer on the vault: name the deployment controller, never a workload identity."
  type        = list(string)
  default     = []
}

//for GCP
variable "secret_version_managers" {
  description = "IAM members allowed to add new versions to every secret. Adding a version does not grant reading one."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for member in var.secret_version_managers :
      can(regex("^(user|group|serviceAccount|principal|principalSet):.+$", member))
    ])
    error_message = "Each entry must be a fully qualified IAM member, for example user:name@example.com."
  }
}
