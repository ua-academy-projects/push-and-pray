module "gcp_project" {
  source = "./modules/gcp/project"

  config = local.config
}

moved {
  from = google_project_service.secretmanager
  to   = google_project_service.required["secretmanager.googleapis.com"]
}

moved {
  from = module.gcp_project[0]
  to   = module.gcp_project
}

moved {
  from = module.gcp_network[0]
  to   = module.gcp_network
}

moved {
  from = module.aws_network[0]
  to   = module.aws_network
}

moved {
  from = module.aws_key_pair[0].aws_key_pair.bootstrap
  to   = module.aws_key_pair.aws_key_pair.bootstrap["this"]
}

moved {
  from = google_project_service.required
  to   = module.gcp_project.google_project_service.required
}

moved {
  from = module.vm
  to   = module.gcp_vm
}
