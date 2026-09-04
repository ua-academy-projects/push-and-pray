# Preserve existing GCP state addresses while moving provider-specific
# resources behind the GCP stack module.
moved {
  from = module.network
  to   = module.gcp.module.network[0]
}

moved {
  from = module.vm
  to   = module.gcp.module.vm
}

moved {
  from = google_project_service.required
  to   = module.gcp.google_project_service.required
}

moved {
  from = google_secret_manager_secret.this
  to   = module.gcp.google_secret_manager_secret.this
}

moved {
  from = google_secret_manager_secret_iam_member.workload_access
  to   = module.gcp.google_secret_manager_secret_iam_member.workload_access
}

moved {
  from = google_secret_manager_secret_iam_member.version_adder
  to   = module.gcp.google_secret_manager_secret_iam_member.version_adder
}
