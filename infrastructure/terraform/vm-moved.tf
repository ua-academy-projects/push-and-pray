moved {
  from = module.gcp_vm["bastion"].google_service_account.workload
  to   = module.gcp_vm.google_service_account.workload["bastion"]
}

moved {
  from = module.gcp_vm["bastion"].google_compute_address.public[0]
  to   = module.gcp_vm.google_compute_address.public["bastion"]
}

moved {
  from = module.gcp_vm["bastion"].google_compute_instance.workload
  to   = module.gcp_vm.google_compute_instance.workload["bastion"]
}

moved {
  from = module.aws_vm["bastion"].data.aws_iam_policy_document.assume_role
  to   = module.aws_vm.data.aws_iam_policy_document.assume_role["bastion"]
}

moved {
  from = module.aws_vm["bastion"].data.aws_ssm_parameter.image
  to   = module.aws_vm.data.aws_ssm_parameter.image["bastion"]
}

moved {
  from = module.aws_vm["bastion"].aws_iam_role.workload
  to   = module.aws_vm.aws_iam_role.workload["bastion"]
}

moved {
  from = module.aws_vm["bastion"].aws_iam_instance_profile.workload
  to   = module.aws_vm.aws_iam_instance_profile.workload["bastion"]
}

moved {
  from = module.aws_vm["bastion"].aws_instance.workload
  to   = module.aws_vm.aws_instance.workload["bastion"]
}

moved {
  from = module.aws_vm["bastion"].aws_eip.public[0]
  to   = module.aws_vm.aws_eip.public["bastion"]
}

moved {
  from = module.gcp_vm["infra"].google_service_account.workload
  to   = module.gcp_vm.google_service_account.workload["infra"]
}

moved {
  from = module.gcp_vm["infra"].google_compute_address.public[0]
  to   = module.gcp_vm.google_compute_address.public["infra"]
}

moved {
  from = module.gcp_vm["infra"].google_compute_instance.workload
  to   = module.gcp_vm.google_compute_instance.workload["infra"]
}

moved {
  from = module.aws_vm["infra"].data.aws_iam_policy_document.assume_role
  to   = module.aws_vm.data.aws_iam_policy_document.assume_role["infra"]
}

moved {
  from = module.aws_vm["infra"].data.aws_ssm_parameter.image
  to   = module.aws_vm.data.aws_ssm_parameter.image["infra"]
}

moved {
  from = module.aws_vm["infra"].aws_iam_role.workload
  to   = module.aws_vm.aws_iam_role.workload["infra"]
}

moved {
  from = module.aws_vm["infra"].aws_iam_instance_profile.workload
  to   = module.aws_vm.aws_iam_instance_profile.workload["infra"]
}

moved {
  from = module.aws_vm["infra"].aws_instance.workload
  to   = module.aws_vm.aws_instance.workload["infra"]
}

moved {
  from = module.aws_vm["infra"].aws_eip.public[0]
  to   = module.aws_vm.aws_eip.public["infra"]
}

moved {
  from = module.gcp_vm["history"].google_service_account.workload
  to   = module.gcp_vm.google_service_account.workload["history"]
}

moved {
  from = module.gcp_vm["history"].google_compute_address.public[0]
  to   = module.gcp_vm.google_compute_address.public["history"]
}

moved {
  from = module.gcp_vm["history"].google_compute_instance.workload
  to   = module.gcp_vm.google_compute_instance.workload["history"]
}

moved {
  from = module.aws_vm["history"].data.aws_iam_policy_document.assume_role
  to   = module.aws_vm.data.aws_iam_policy_document.assume_role["history"]
}

moved {
  from = module.aws_vm["history"].data.aws_ssm_parameter.image
  to   = module.aws_vm.data.aws_ssm_parameter.image["history"]
}

moved {
  from = module.aws_vm["history"].aws_iam_role.workload
  to   = module.aws_vm.aws_iam_role.workload["history"]
}

moved {
  from = module.aws_vm["history"].aws_iam_instance_profile.workload
  to   = module.aws_vm.aws_iam_instance_profile.workload["history"]
}

moved {
  from = module.aws_vm["history"].aws_instance.workload
  to   = module.aws_vm.aws_instance.workload["history"]
}

moved {
  from = module.aws_vm["history"].aws_eip.public[0]
  to   = module.aws_vm.aws_eip.public["history"]
}

moved {
  from = module.gcp_vm["fetcher"].google_service_account.workload
  to   = module.gcp_vm.google_service_account.workload["fetcher"]
}

moved {
  from = module.gcp_vm["fetcher"].google_compute_address.public[0]
  to   = module.gcp_vm.google_compute_address.public["fetcher"]
}

moved {
  from = module.gcp_vm["fetcher"].google_compute_instance.workload
  to   = module.gcp_vm.google_compute_instance.workload["fetcher"]
}

moved {
  from = module.aws_vm["fetcher"].data.aws_iam_policy_document.assume_role
  to   = module.aws_vm.data.aws_iam_policy_document.assume_role["fetcher"]
}

moved {
  from = module.aws_vm["fetcher"].data.aws_ssm_parameter.image
  to   = module.aws_vm.data.aws_ssm_parameter.image["fetcher"]
}

moved {
  from = module.aws_vm["fetcher"].aws_iam_role.workload
  to   = module.aws_vm.aws_iam_role.workload["fetcher"]
}

moved {
  from = module.aws_vm["fetcher"].aws_iam_instance_profile.workload
  to   = module.aws_vm.aws_iam_instance_profile.workload["fetcher"]
}

moved {
  from = module.aws_vm["fetcher"].aws_instance.workload
  to   = module.aws_vm.aws_instance.workload["fetcher"]
}

moved {
  from = module.aws_vm["fetcher"].aws_eip.public[0]
  to   = module.aws_vm.aws_eip.public["fetcher"]
}

moved {
  from = module.gcp_vm["ui"].google_service_account.workload
  to   = module.gcp_vm.google_service_account.workload["ui"]
}

moved {
  from = module.gcp_vm["ui"].google_compute_address.public[0]
  to   = module.gcp_vm.google_compute_address.public["ui"]
}

moved {
  from = module.gcp_vm["ui"].google_compute_instance.workload
  to   = module.gcp_vm.google_compute_instance.workload["ui"]
}

moved {
  from = module.aws_vm["ui"].data.aws_iam_policy_document.assume_role
  to   = module.aws_vm.data.aws_iam_policy_document.assume_role["ui"]
}

moved {
  from = module.aws_vm["ui"].data.aws_ssm_parameter.image
  to   = module.aws_vm.data.aws_ssm_parameter.image["ui"]
}

moved {
  from = module.aws_vm["ui"].aws_iam_role.workload
  to   = module.aws_vm.aws_iam_role.workload["ui"]
}

moved {
  from = module.aws_vm["ui"].aws_iam_instance_profile.workload
  to   = module.aws_vm.aws_iam_instance_profile.workload["ui"]
}

moved {
  from = module.aws_vm["ui"].aws_instance.workload
  to   = module.aws_vm.aws_instance.workload["ui"]
}

moved {
  from = module.aws_vm["ui"].aws_eip.public[0]
  to   = module.aws_vm.aws_eip.public["ui"]
}
