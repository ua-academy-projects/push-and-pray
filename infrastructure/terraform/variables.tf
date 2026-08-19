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
