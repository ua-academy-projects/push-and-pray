mock_provider "aws" {}

run "startup_preserves_ssh_users" {
  command = plan
  module {
    source = "./modules/aws_vm"
  }
  variables {
    startup_scripts = { history = "#!/bin/sh\necho bootstrap\n" }
  }
  assert {
    condition = (
      yamldecode(aws_instance.workload["history"].user_data).write_files[0].content == var.startup_scripts.history &&
      yamldecode(aws_instance.workload["history"].user_data).runcmd[0][0] == "/usr/local/sbin/oilscope-bootstrap" &&
      length(yamldecode(aws_instance.workload["history"].user_data).users) == length(var.ssh_users) &&
      length(yamldecode(aws_instance.workload["bastion"].user_data).runcmd) == 0
    )
    error_message = "Optional cloud-init bootstrap must preserve configured SSH users and remain opt-in by VM key."
  }
}

run "create_with_current_ami" {
  command = apply
  module {
    source = "./modules/aws_vm"
  }
  override_data {
    target = data.aws_ami.ubuntu["bastion"]
    values = { id = "ami-0123456789abcdef0" }
  }
  assert {
    condition     = aws_instance.workload["bastion"].ami == "ami-0123456789abcdef0"
    error_message = "A new instance must use the currently resolved AMI."
  }
}

run "retain_existing_ami" {
  command = plan
  module {
    source = "./modules/aws_vm"
  }
  override_data {
    target = data.aws_ami.ubuntu["bastion"]
    values = { id = "ami-0fedcba9876543210" }
  }
  assert {
    condition = (
      data.aws_ami.ubuntu["bastion"].id == "ami-0fedcba9876543210" &&
      aws_instance.workload["bastion"].ami == "ami-0123456789abcdef0"
    )
    error_message = "A newer upstream AMI must not change the image of an existing instance."
  }
}

variables {
  config          = merge(jsondecode(file("../../project-config.example.json")), { default_cloud = "aws" })
  resource_prefix = "oilscope-test"
  common_labels   = { managed_by = "terraform" }
  ssh_users       = jsondecode(file("../../project-config.example.json")).ssh_users
  network = {
    management_subnet_id = "subnet-management"
    workload_subnet_id   = "subnet-workload"
    security_group_ids = {
      bastion = "sg-bastion", database = "sg-database", history = "sg-history", fetcher = "sg-fetcher", ui = "sg-ui"
    }
  }
}

run "aws_resource_contract" {
  command = plan
  module {
    source = "./modules/aws_vm"
  }
  assert {
    condition = (
      toset(keys(aws_instance.workload)) == toset(["bastion", "infra", "history", "fetcher", "ui"]) &&
      toset(keys(aws_iam_role.workload)) == toset(keys(aws_instance.workload)) &&
      toset(keys(aws_iam_instance_profile.workload)) == toset(keys(aws_instance.workload)) &&
      toset(keys(aws_eip.public)) == toset(["bastion", "ui"]) &&
      toset(keys(aws_eip_association.public)) == toset(["bastion", "ui"])
    )
    error_message = "AWS VM resources and identities must be keyed consistently, with only bastion and UI Elastic IPs."
  }
  assert {
    condition = alltrue([
      for name, instance in aws_instance.workload :
      instance.tags.Name == "oilscope-test-${name}" &&
      aws_iam_role.workload[name].name == "oilscope-test-${name}-role" &&
      aws_iam_instance_profile.workload[name].name == "oilscope-test-${name}-profile" &&
      instance.subnet_id == (contains(["bastion", "ui"], name) ? "subnet-management" : "subnet-workload") &&
      instance.instance_type == var.config.cloud_mappings.sizes[var.config.vms[name].size].aws &&
      instance.root_block_device[0].volume_type == var.config.cloud_mappings.disk_types[var.config.vms[name].boot_disk.type].aws &&
      instance.root_block_device[0].volume_size == var.config.vms[name].boot_disk.size_gb &&
      instance.root_block_device[0].encrypted &&
      instance.metadata_options[0].http_tokens == "required" &&
      instance.associate_public_ip_address == contains(["bastion", "ui"], name) &&
      toset(instance.vpc_security_group_ids) == toset([var.network.security_group_ids[var.config.vms[name].role]])
    ])
    error_message = "AWS names, subnet/security-group assignment, machine/disk mappings and instance security settings must be preserved."
  }
}

run "invalid_aws_disk" {
  command = plan
  module {
    source = "./modules/aws_vm"
  }
  variables {
    config = merge(var.config, {
      vms = merge(var.config.vms, {
        history = merge(var.config.vms.history, { boot_disk = { size_gb = 7, type = "balanced" } })
      })
    })
  }
  expect_failures = [aws_instance.workload]
}

run "invalid_aws_zone" {
  command = plan
  module {
    source = "./modules/aws_vm"
  }
  variables {
    config = merge(var.config, {
      cloud_mappings = merge(var.config.cloud_mappings, {
        regions = {
          (var.config.default_region) = { aws = { region = "eu-central-1", zone = "us-east-1a" } }
        }
      })
    })
  }
  expect_failures = [aws_instance.workload]
}

run "no_aws_vms" {
  command = plan
  module {
    source = "./modules/aws_vm"
  }
  variables {
    config  = merge(var.config, { default_cloud = "gcp", cloud_mappings = {} })
    network = null
  }
  assert {
    condition     = length(output.vms) == 0 && length(output.resolved_vms) == 0
    error_message = "An unused provider must not resolve VM mappings or create resources."
  }
}

run "invalid_regions_mapping" {
  command = plan
  module {
    source = "./modules/aws_vm"
  }
  variables {
    config = merge(var.config, {
      cloud_mappings = merge(var.config.cloud_mappings, { regions = {} })
    })
  }
  expect_failures = [var.config]
}

run "invalid_sizes_mapping" {
  command = plan
  module {
    source = "./modules/aws_vm"
  }
  variables {
    config = merge(var.config, {
      cloud_mappings = merge(var.config.cloud_mappings, { sizes = {} })
    })
  }
  expect_failures = [var.config]
}

run "invalid_disk_types_mapping" {
  command = plan
  module {
    source = "./modules/aws_vm"
  }
  variables {
    config = merge(var.config, {
      cloud_mappings = merge(var.config.cloud_mappings, { disk_types = {} })
    })
  }
  expect_failures = [var.config]
}

run "invalid_images_mapping" {
  command = plan
  module {
    source = "./modules/aws_vm"
  }
  variables {
    config = merge(var.config, {
      cloud_mappings = merge(var.config.cloud_mappings, { images = {} })
    })
  }
  expect_failures = [var.config]
}
