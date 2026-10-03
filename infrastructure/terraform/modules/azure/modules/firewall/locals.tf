locals {
  # Rules and for_each keys take strings; the configuration holds numbers.
  ui_public_ports = [for port in var.config.network.ui_public_ports : tostring(port)]

  # Same five scopes GCP expresses as network tags and AWS as security groups.
  # On Azure a scope is an application security group a network interface
  # joins, and every rule lives in one security group on the subnets.
  scopes = ["bastion", "infra", "history", "fetcher", "ui"]

  workload_scopes = ["infra", "history", "fetcher", "ui"]

  # The workloads that talk to whatever the infra VM serves.
  infra_client_scopes = ["fetcher", "history", "ui"]

  # Rules are evaluated by priority, lowest first. The allow rules sit in one
  # band, the database module adds its own at the end of it, and the deny that
  # makes the network default-closed comes last, below all of them.
  priorities = {
    bastion_ssh           = 100
    bastion_ssh_bootstrap = 110
    workload_ssh          = 120
    ui_web                = 130
    history_api           = 140
    postgresql            = 150
    amqp                  = 160
    redis                 = 170
    deny_vnet_inbound     = 4000
  }
}
