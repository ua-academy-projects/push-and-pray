resource "terraform_data" "config_validation" {
  input = local.clouds

  lifecycle {
    precondition {
      condition     = contains(local.supported_clouds, local.default_cloud)
      error_message = "default_cloud is \"${local.default_cloud}\". Supported clouds: ${join(", ", local.supported_clouds)}."
    }

    precondition {
      condition = alltrue([
        for cloud in local.clouds : contains(local.supported_clouds, cloud)
      ])
      error_message = "One or more vms[*].cloud values are unsupported. Requested: ${join(", ", local.clouds)}. Supported: ${join(", ", local.supported_clouds)}."
    }

    precondition {
      condition = alltrue([
        for cloud in local.clouds : local.region[cloud] != null && local.zone[cloud] != null
      ])
      error_message = "location \"${local.location}\" has no mapping for every cloud in use (${join(", ", local.clouds)})."
    }

    precondition {
      condition     = length(local.misplaced_ips) == 0
      error_message = "internal_ip is outside the subnet the VM is placed in: ${join(", ", local.misplaced_ips)}. A VM that needs a public IP goes in the management subnet on clouds where the route to the internet belongs to the subnet."
    }

    precondition {
      condition     = length(local.aws_reserved_ips) == 0
      error_message = "internal_ip uses one of the first four addresses of its subnet, which AWS reserves: ${join(", ", local.aws_reserved_ips)}."
    }

    precondition {
      condition     = alltrue([for name, vm in local.vms : vm.machine_type != null])
      error_message = "One or more vms[*].size values have no mapping for the cloud they target."
    }

    precondition {
      condition     = alltrue([for name, vm in local.vms : vm.boot_disk_type != null])
      error_message = "One or more vms[*].boot_disk.type values have no mapping for the cloud they target."
    }

    precondition {
      condition     = alltrue([for name, vm in local.vms : vm.image != null])
      error_message = "One or more vms[*].os values have no mapping for the cloud they target."
    }

    precondition {
      condition     = !local.has_gcp || coalesce(local.gcp_project_id, "") != ""
      error_message = "At least one VM targets gcp, so the configuration must contain gcp.project_id."
    }

    precondition {
      condition     = !local.has_aws || length(lookup(lookup(local.config, "aws", {}), "regions", [])) > 0
      error_message = "At least one VM targets aws, so the configuration must contain aws.regions for the dynamic inventory to search."
    }
  }
}
