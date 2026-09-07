mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }
}

variables {
  config = merge(jsondecode(file("../../project-config.example.json")), {
    default_cloud = "aws"
  })
  network = {
    management_subnet_id = "subnet-00000000000000001"
    vm_subnet_id         = "subnet-00000000000000002"
    security_group_ids_by_role = {
      bastion  = "sg-00000000000000001"
      database = "sg-00000000000000002"
      history  = "sg-00000000000000003"
      fetcher  = "sg-00000000000000004"
      ui       = "sg-00000000000000005"
    }
  }
  instance_profile_names = {
    infra   = "infra-runtime"
    history = "history-runtime"
    fetcher = "fetcher-runtime"
    ui      = "ui-runtime"
  }
}

run "public_ui_private_database" {
  command = plan

  module {
    source = "./modules/aws_vm"
  }

  assert {
    condition = (
      aws_instance.vms["ui"].subnet_id == var.network.management_subnet_id &&
      aws_instance.vms["ui"].private_ip == "10.0.0.5" &&
      aws_instance.vms["infra"].subnet_id == var.network.vm_subnet_id &&
      aws_instance.vms["infra"].private_ip == "10.0.1.5"
    )
    error_message = "UI must use its AWS override in the public subnet; database must remain private."
  }

  assert {
    condition     = toset(keys(aws_eip.public)) == toset(["bastion", "ui"])
    error_message = "Only bastion and UI may have public addresses."
  }

  assert {
    condition = (
      aws_instance.vms["fetcher"].iam_instance_profile == "fetcher-runtime" &&
      aws_instance.vms["bastion"].iam_instance_profile == null
    )
    error_message = "Application VMs must use their assigned identity; bastion must not get a runtime role."
  }

  assert {
    condition = (
      yamldecode(aws_instance.vms["ui"].user_data).ssh_pwauth == false &&
      length(yamldecode(aws_instance.vms["ui"].user_data).users) == length(var.config.ssh_users) + 1
    )
    error_message = "Cloud-init must configure the JSON SSH users with password authentication disabled."
  }
}

run "gcp_config_creates_no_aws_vms" {
  command = plan

  module {
    source = "./modules/aws_vm"
  }

  variables {
    config = merge(jsondecode(file("../../project-config.example.json")), {
      default_cloud = "gcp"
    })
  }

  assert {
    condition     = length(aws_instance.vms) == 0 && length(aws_eip.public) == 0 && length(data.aws_ami.images) == 0
    error_message = "A GCP-only configuration must not create AWS VMs, addresses, or AMI lookups."
  }
}
