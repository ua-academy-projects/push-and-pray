mock_provider "google" {}

run "startup_is_optional_and_not_role_specific" {
  command = plan
  module {
    source = "./modules/vm"
  }
  variables {
    startup_scripts = { history = "#!/bin/sh\necho bootstrap\n" }
  }
  assert {
    condition = (
      google_compute_instance.workload["history"].metadata["startup-script"] == var.startup_scripts.history &&
      !contains(keys(google_compute_instance.workload["bastion"].metadata), "startup-script")
    )
    error_message = "Startup data must be opt-in for any VM key, without hard-coded bastion behavior in the module."
  }
}

variables {
  config          = jsondecode(file("../../project-config.example.json"))
  resource_prefix = "oilscope-test"
  common_labels   = { managed_by = "terraform" }
  ssh_users       = jsondecode(file("../../project-config.example.json")).ssh_users
  network = {
    management_subnet_id = "management-subnet"
    workload_subnet_id   = "workload-subnet"
  }
}

run "gcp_resource_contract" {
  command = plan
  module {
    source = "./modules/vm"
  }

  assert {
    condition = (
      toset(keys(google_compute_instance.workload)) == toset(["bastion", "infra", "history", "fetcher", "ui"]) &&
      toset(keys(google_service_account.workload)) == toset(keys(google_compute_instance.workload)) &&
      toset(keys(google_compute_address.public)) == toset(["bastion", "ui"])
    )
    error_message = "The migration must retain five instances, five identities and exactly two public addresses under their original VM keys."
  }
  assert {
    condition = alltrue([
      for name, instance in google_compute_instance.workload :
      instance.name == "oilscope-test-${name}" &&
      google_service_account.workload[name].account_id == instance.name &&
      instance.network_interface[0].subnetwork == (name == "bastion" ? "management-subnet" : "workload-subnet") &&
      instance.machine_type == var.config.cloud_mappings.sizes[var.config.vms[name].size].gcp &&
      instance.boot_disk[0].initialize_params[0].type == var.config.cloud_mappings.disk_types[var.config.vms[name].boot_disk.type].gcp &&
      instance.boot_disk[0].initialize_params[0].size == var.config.vms[name].boot_disk.size_gb &&
      instance.boot_disk[0].initialize_params[0].image == format("projects/%s/global/images/family/%s", var.config.cloud_mappings.images[var.config.vms[name].image].gcp.project, var.config.cloud_mappings.images[var.config.vms[name].image].gcp.family) &&
      instance.metadata["enable-oslogin"] == "FALSE" &&
      !contains(keys(instance.metadata), "startup-script") &&
      length(instance.network_interface[0].access_config) == (contains(["bastion", "ui"], name) ? 1 : 0)
    ])
    error_message = "VM names, identity names, subnet placement, disk/image mappings, metadata and public IP behavior must be preserved."
  }
  assert {
    condition     = toset(google_compute_instance.workload["infra"].tags) == toset(["oilscope-test-infra"])
    error_message = "The database role must retain its infra firewall tag."
  }
}

run "invalid_gcp_disk" {
  command = plan
  module {
    source = "./modules/vm"
  }
  variables {
    config = merge(var.config, {
      vms = merge(var.config.vms, {
        history = merge(var.config.vms.history, { boot_disk = { size_gb = 9, type = "balanced" } })
      })
    })
  }
  expect_failures = [google_compute_instance.workload]
}

run "invalid_gcp_zone" {
  command = plan
  module {
    source = "./modules/vm"
  }
  variables {
    config = merge(var.config, {
      cloud_mappings = merge(var.config.cloud_mappings, {
        regions = {
          (var.config.default_region) = { gcp = { region = "europe-west1", zone = "us-central1-a" } }
        }
      })
    })
  }
  expect_failures = [google_compute_instance.workload]
}

run "no_gcp_vms" {
  command = plan
  module {
    source = "./modules/vm"
  }
  variables {
    config  = merge(var.config, { default_cloud = "aws", cloud_mappings = {} })
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
    source = "./modules/vm"
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
    source = "./modules/vm"
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
    source = "./modules/vm"
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
    source = "./modules/vm"
  }
  variables {
    config = merge(var.config, {
      cloud_mappings = merge(var.config.cloud_mappings, { images = {} })
    })
  }
  expect_failures = [var.config]
}
