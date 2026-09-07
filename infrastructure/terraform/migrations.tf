moved {
  from = module.network
  to   = module.network[0]
}

# VM instance keys now belong to resources inside the singleton VM modules.
moved {
  from = module.vm["bastion"].google_compute_instance.workload
  to   = module.vm.google_compute_instance.workload["bastion"]
}

moved {
  from = module.vm["bastion"].google_service_account.workload
  to   = module.vm.google_service_account.workload["bastion"]
}

moved {
  from = module.vm["bastion"].google_compute_address.public[0]
  to   = module.vm.google_compute_address.public["bastion"]
}

moved {
  from = module.vm["fetcher"].google_compute_instance.workload
  to   = module.vm.google_compute_instance.workload["fetcher"]
}

moved {
  from = module.vm["fetcher"].google_service_account.workload
  to   = module.vm.google_service_account.workload["fetcher"]
}

moved {
  from = module.vm["history"].google_compute_instance.workload
  to   = module.vm.google_compute_instance.workload["history"]
}

moved {
  from = module.vm["history"].google_service_account.workload
  to   = module.vm.google_service_account.workload["history"]
}

moved {
  from = module.vm["infra"].google_compute_instance.workload
  to   = module.vm.google_compute_instance.workload["infra"]
}

moved {
  from = module.vm["infra"].google_service_account.workload
  to   = module.vm.google_service_account.workload["infra"]
}

moved {
  from = module.vm["ui"].google_compute_instance.workload
  to   = module.vm.google_compute_instance.workload["ui"]
}

moved {
  from = module.vm["ui"].google_service_account.workload
  to   = module.vm.google_service_account.workload["ui"]
}

moved {
  from = module.vm["ui"].google_compute_address.public[0]
  to   = module.vm.google_compute_address.public["ui"]
}

moved {
  from = module.network[0].google_compute_firewall.bastion_ssh
  to   = module.gcp_firewall[0].google_compute_firewall.bastion_ssh
}

moved {
  from = module.network[0].google_compute_firewall.workload_ssh
  to   = module.gcp_firewall[0].google_compute_firewall.workload_ssh
}

moved {
  from = module.network[0].google_compute_firewall.ui_web
  to   = module.gcp_firewall[0].google_compute_firewall.ui_web
}

moved {
  from = module.network[0].google_compute_firewall.history_api
  to   = module.gcp_firewall[0].google_compute_firewall.history_api
}

moved {
  from = module.network[0].google_compute_firewall.postgresql
  to   = module.gcp_firewall[0].google_compute_firewall.postgresql
}
