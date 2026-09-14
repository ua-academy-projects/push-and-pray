locals {
  # Every VM that runs the Ops Agent: the workloads and the bastion. The
  # bastion's identity is count-based, so it joins only when the cloud is active.
  agent_identities = merge(
    { for name in keys(local.workload_vms) : name => module.identity[name].member },
    local.is_active ? { bastion = module.bastion_identity[0].member } : {},
  )

  # Logs and host metrics; the agent ships both.
  agent_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]

  agent_bindings = {
    for pair in setproduct(sort(keys(local.agent_identities)), local.agent_roles) :
    "${pair[0]}/${pair[1]}" => {
      member = local.agent_identities[pair[0]]
      role   = pair[1]
    }
  }
}

resource "google_project_iam_member" "agent" {
  for_each = local.agent_bindings

  project = local.profile.project_id
  role    = each.value.role
  member  = each.value.member
}
