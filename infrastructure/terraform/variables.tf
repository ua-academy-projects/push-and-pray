variable "project_config_path" {
  description = "path to the JSON configuration file"
  type        = string
}

variable "ssh_users" {
  description = <<-EOT
    One PUBLIC SSH key per person, keyed by the Linux username.
    Private keys are never generated, accepted or stored by this configuration.
  EOT
  type        = map(string)
}

variable "secret_version_managers" {
  description = <<-EOT
    IAM principals allowed to add new versions to the Secret Manager secrets
    created by this configuration, in full member form, for example
    "user:name@example.com" or
    "serviceAccount:deployer@project.iam.gserviceaccount.com".

    This grants write-only access: these principals can store a new secret
    value, but cannot read existing ones. Secret values themselves are never
    accepted as Terraform input.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for member in var.secret_version_managers :
      can(regex("^(user|group|serviceAccount|principal|principalSet):.+$", member))
    ])
    error_message = "Each entry must be a full IAM member string, for example user:you@example.com or serviceAccount:deployer@project.iam.gserviceaccount.com."
  }
}
