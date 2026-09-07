variable "config" {
    type = any
}

variable "enable_bastion_ssh_bootstrap" {
    type = bool
    default = false
}

variable "aws_secret_version_managers" {
    description = "AWS IAM principal ARNs allowed to add new versions to every AWS secret. Adding a version does not grant reading one."
    type        = list(string)
    default     = []
}
