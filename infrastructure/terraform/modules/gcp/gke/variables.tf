variable "project_id" {
  description = "GCP project that owns the GKE cluster."
  type        = string
}

variable "resource_prefix" {
  description = "Prefix used for GKE resources."
  type        = string
}

variable "location" {
  description = "GCP zone hosting this zonal GKE Standard cluster."
  type        = string
}

variable "network_id" {
  description = "Self-link of the VPC used by the cluster."
  type        = string
}

variable "subnetwork_name" {
  description = "Workload subnet name containing the GKE secondary ranges."
  type        = string
}

variable "settings" {
  description = "GKE settings from the shared project configuration."
  type        = any
}

variable "labels" {
  description = "Common labels applied to GKE resources."
  type        = map(string)
}
