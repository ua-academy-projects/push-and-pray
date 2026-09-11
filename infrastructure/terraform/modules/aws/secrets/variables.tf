variable "config" {
    type = any
}

variable "selected_vms" {
    description = "VMs assigned to this cloud, cloud-filtered by the parent module."
    type        = any
}

variable "iam_role_names" {
    description = "IAM role name per VM key, from the iam module."
    type        = map(string)
}

variable "aws_secret_version_managers" {
    description = "AWS IAM principal ARNs allowed to add new versions to every AWS secret. Adding a version does not grant reading one."
    type        = list(string)
    default     = []
}
