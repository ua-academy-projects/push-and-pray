variable "name" {
  description = "Name used for the VM and its service account."
  type        = string
}

variable "subnetwork_id" {
  description = "ID of the subnet where the VM is created."
  type        = string
}

variable "network_tags" {
  description = "Effective network tags attached to the workload VM."
  type        = list(string)
}

variable "role" {
  description = "Functional role of the workload, independent from its resource name."
  type        = string
}

variable "machine_type" {
  description = "Compute Engine machine type for the workload VM."
  type        = string
}

variable "image" {
  description = "Boot image used by the VM."
  type        = string
}

variable "internal_ip" {
  description = "Static internal IPv4 address assigned to the VM."
  type        = string
}

variable "boot_disk_size_gb" {
  description = "Size of the boot disk in GiB."
  type        = number
}

variable "boot_disk_type" {
  description = "Persistent Disk type used by the boot disk."
  type        = string
}

variable "assign_public_ip" {
  description = "Whether to create and assign a static external IP address."
  type        = bool
  default     = false
}

variable "automation_role" {
  description = "Non-secret automation role passed to the cloud-init bootstrap process."
  type        = string
}

variable "registry_repository" {
  description = "Non-secret container registry repository used by deployment automation."
  type        = string
}

variable "image_sha" {
  description = "Immutable 40-character Git commit SHA used as the application image tag."
  type        = string
}

variable "docker_version" {
  description = "Exact Docker Engine apt version pinned by the cloud-init bootstrap. Verify with `apt-cache madison docker-ce` before bumping."
  type        = string
  default     = "5:29.7.2-1~ubuntu.26.04~resolute"
}

variable "labels" {
  description = "Labels applied to resources that support them."
  type        = map(string)
}
