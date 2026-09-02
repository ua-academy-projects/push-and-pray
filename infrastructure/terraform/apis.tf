module "gcp_project" {
  count  = contains(local.enabled_clouds, "gcp") ? 1 : 0
  source = "./modules/gcp/project"
}

moved {
  from = google_project_service.secretmanager
  to   = google_project_service.required["secretmanager.googleapis.com"]
}

moved {
  from = google_project_service.required
  to   = module.gcp_project[0].google_project_service.required
}

moved {
  from = module.network
  to   = module.gcp_network[0]
}

moved {
  from = module.vm
  to   = module.gcp_vm
}

moved {
  from = aws_key_pair.bootstrap
  to   = module.aws_key_pair[0].aws_key_pair.bootstrap
}
