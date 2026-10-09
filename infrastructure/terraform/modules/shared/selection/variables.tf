variable "config" {
  description = "The whole decoded configuration, with node_defaults already merged into every node and every node's cloud resolved by the root module."
  type        = any
  nullable    = false

  # Cross-references JSON Schema cannot express, because a label is only valid
  # against a sibling map in the same document.
  #
  # Every check is skipped when this cloud hosts no node: the calling module
  # then builds nothing, so nothing about its profile has to hold.

  validation {
    condition = (
      length([for name, node in var.config.nodes : name if node.cloud == var.cloud]) == 0
      || can(var.config.clouds[var.cloud])
    )
    error_message = "Nodes are placed on a cloud that clouds declares no profile for."
  }

  validation {
    condition = (
      length([for name, node in var.config.nodes : name if node.cloud == var.cloud]) == 0
      || alltrue([
        for field in var.required_profile_fields :
        can(var.config.clouds[var.cloud][field])
      ])
    )
    error_message = "This cloud's profile must declare: ${join(", ", var.required_profile_fields)}."
  }

  validation {
    condition = (
      length([for name, node in var.config.nodes : name if node.cloud == var.cloud]) == 0
      || alltrue([
        for name, node in var.config.nodes :
        contains(keys(try(var.config.clouds[var.cloud].machine_sizes, {})), node.size)
        if node.cloud == var.cloud
      ])
    )
    error_message = "Every node on this cloud must use a size label declared in its machine_sizes."
  }

  validation {
    condition = (
      length([for name, node in var.config.nodes : name if node.cloud == var.cloud]) == 0
      || alltrue([
        for name, node in var.config.nodes :
        contains(keys(try(var.config.clouds[var.cloud].images, {})), node.image)
        if node.cloud == var.cloud
      ])
    )
    error_message = "Every node on this cloud must use an image label declared in its images."
  }

  validation {
    condition = (
      length([for name, node in var.config.nodes : name if node.cloud == var.cloud]) == 0
      || alltrue([
        for name, node in var.config.nodes :
        contains(keys(try(var.config.clouds[var.cloud].disk_types, {})), node.boot_disk.type)
        if node.cloud == var.cloud
      ])
    )
    error_message = "Every node on this cloud must use a boot disk label declared in its disk_types."
  }

  validation {
    condition = (
      length([for name, node in var.config.nodes : name if node.cloud == var.cloud]) == 0
      || alltrue(flatten([
        for dictionary, pattern in var.profile_value_patterns : [
          for label, value in try(var.config.clouds[var.cloud][dictionary], {}) :
          can(regex(pattern, value))
        ]
      ]))
    )
    error_message = "This cloud's lookup maps hold values its provider does not accept: ${join(", ", flatten([
      for dictionary, pattern in var.profile_value_patterns : [
        for label, value in try(var.config.clouds[var.cloud][dictionary], {}) :
        "${dictionary}.${label}=${value}" if !can(regex(pattern, value))
      ]
    ]))}."
  }

  # Masking a subnet's first address with the network's prefix length gives
  # the network's own first address exactly when the subnet starts inside it;
  # a longer prefix then keeps it inside to the end.
  validation {
    condition = (
      length([for name, node in var.config.nodes : name if node.cloud == var.cloud]) == 0
      || alltrue([
        for subnet in values(try(var.config.clouds[var.cloud].subnets, {})) :
        try(
          tonumber(split("/", subnet)[1]) >= tonumber(split("/", var.config.clouds[var.cloud].network_cidr)[1])
          && cidrhost("${cidrhost(subnet, 0)}/${split("/", var.config.clouds[var.cloud].network_cidr)[1]}", 0) == cidrhost(var.config.clouds[var.cloud].network_cidr, 0),
          false,
        )
      ])
    )
    error_message = "Every subnet of this cloud must lie inside its network_cidr: the bastion advertises network_cidr, and an address outside it would be unreachable from the other clouds."
  }
}

variable "cloud" {
  description = "Which cloud is asking. The calling module's own name for itself."
  type        = string
  nullable    = false
}

variable "required_profile_fields" {
  description = "Profile fields this provider cannot work without, for example project_id on GCP or subscription_id on Azure. A list rather than a condition on the cloud name, so adding a provider adds an argument and not a branch."
  type        = list(string)
  default     = []
}

variable "profile_value_patterns" {
  description = "Per lookup map, a regular expression every value in it must match on this provider - for example gp3 is a valid disk type on AWS and nowhere else. A map rather than a condition on the cloud name, so adding a provider adds an argument and not a branch. Checks the whole dictionary, including labels no node uses yet."
  type        = map(string)
  default     = {}
}
