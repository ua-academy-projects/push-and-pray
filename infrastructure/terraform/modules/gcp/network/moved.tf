moved {
  from = google_compute_network.main
  to   = google_compute_network.main["this"]
}

moved {
  from = google_compute_subnetwork.management
  to   = google_compute_subnetwork.management["this"]
}

moved {
  from = google_compute_subnetwork.workload
  to   = google_compute_subnetwork.workload["this"]
}

moved {
  from = google_compute_firewall.bastion_ssh
  to   = google_compute_firewall.bastion_ssh["this"]
}

moved {
  from = google_compute_firewall.bastion_ssh_bootstrap[0]
  to   = google_compute_firewall.bastion_ssh_bootstrap["this"]
}

moved {
  from = google_compute_firewall.workload_ssh
  to   = google_compute_firewall.workload_ssh["this"]
}

moved {
  from = google_compute_firewall.ui_web
  to   = google_compute_firewall.ui_web["this"]
}

moved {
  from = google_compute_router.main
  to   = google_compute_router.main["this"]
}

moved {
  from = google_compute_router_nat.main
  to   = google_compute_router_nat.main["this"]
}

moved {
  from = google_compute_network.main["this"]
  to   = google_compute_network.main["europe"]
}

moved {
  from = google_compute_subnetwork.management["this"]
  to   = google_compute_subnetwork.management["europe"]
}

moved {
  from = google_compute_subnetwork.workload["this"]
  to   = google_compute_subnetwork.workload["europe"]
}

moved {
  from = google_compute_firewall.bastion_ssh["this"]
  to   = google_compute_firewall.bastion_ssh["europe"]
}

moved {
  from = google_compute_firewall.bastion_ssh_bootstrap["this"]
  to   = google_compute_firewall.bastion_ssh_bootstrap["europe"]
}

moved {
  from = google_compute_firewall.workload_ssh["this"]
  to   = google_compute_firewall.workload_ssh["europe"]
}

moved {
  from = google_compute_firewall.ui_web["this"]
  to   = google_compute_firewall.ui_web["europe"]
}

moved {
  from = google_compute_router.main["this"]
  to   = google_compute_router.main["europe"]
}

moved {
  from = google_compute_router_nat.main["this"]
  to   = google_compute_router_nat.main["europe"]
}
