check "config_version" {
  assert {
    condition     = local.config.config_version == 1
    error_message = "config_version must be 1"
  }
}

check "region_consistency" {
  assert {
    condition     = startswith(local.config.zone, "${local.config.region}-")
    error_message = "zone must belong to the specified region"
  }
}

check "cidrs_valid_and_non_overlapping" {
  assert {
    condition     = can(cidrhost(local.config.network.management_subnet_cidr, 0)) && can(cidrhost(local.config.network.workload_subnet_cidr, 0))
    error_message = "must be both valid IPv4 CIDR blocks."
  }

  assert {
    condition     = local.config.network.management_subnet_cidr != local.config.network.workload_subnet_cidr
    error_message = "management_subnet_cidr and workload_subnet_cidr must not be identical."
  }
}
check "unique_internal_ips" {
  assert {
    condition     = length([for vm in local.config.vms : vm.internal_ip]) == length(distinct([for vm in local.config.vms : vm.internal_ip]))
    error_message = "internal_ip values in vms must be unique"
  }
}

check "supported_vm_roles" {
  assert {
    condition = alltrue([
      for vm in local.config.vms : contains(["infra", "history", "fetcher", "ui"], vm.role)
    ])
    error_message = "Every vm.role must be one of: infra, history, fetcher, ui."
  }
}

check "supported_automation_roles" {
  assert {
    condition = alltrue([
      for vm in local.config.vms : contains(["none"], vm.automation_role)
    ])
    error_message = "Every vm.automation_role must be one of: none"
  }
}

check "valid_disk_sizes_and_machine_types" {
  assert {
    condition = alltrue([
      for vm in local.config.vms : vm.boot_disk_size_gb >= 10
    ])
    error_message = "Every vm.boot_disk_size_gb must be at least 10 GiB."
  }

  assert {
    condition = alltrue([
      for vm in local.config.vms : contains(["e2-micro", "e2-small", "e2-medium", "e2-standard-2"], vm.machine_type)
    ])
    error_message = "Every vm.machine_type must be one of the supported machine types."
  }
}

check "network_tags_valid" {
  assert {
    condition = alltrue([
      for vm in local.config.vms : length(vm.network_tags) == length(distinct(vm.network_tags))
    ])
    error_message = "Each vm's network_tags must not contain duplicate tags."
  }

  assert {
    condition = alltrue([
      for vm in local.config.vms : alltrue([
        for tag in vm.network_tags : can(regex("^[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$", tag))
      ])
    ])
    error_message = "Every additional network tag must be a valid lowercase GCP network tag of at most 63 characters."
  }
}

check "required_vm_fields" {
  assert {
    condition = alltrue([
      for vm in local.config.vms : alltrue([
        for field in ["name", "role", "machine_type", "internal_ip", "assign_public_ip", "network_tags", "boot_image", "boot_disk_size_gb", "boot_disk_type", "automation_role", "secret_ids"] :
        contains(keys(vm), field)
      ])
    ])
    error_message = "Every VM object in vms must contain all required fields: name, role, machine_type, internal_ip, assign_public_ip, network_tags, boot_image, boot_disk_size_gb, boot_disk_type, automation_role, secret_ids."
  }
}
