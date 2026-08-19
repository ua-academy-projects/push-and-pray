# Generic VM module

Creates one Compute Engine VM with a reserved internal address, an optional
reserved external address, a boot disk, network tags, metadata and a
caller-provided service account.

The module applies the shared compute security baseline: no IP forwarding,
Shielded VM Secure Boot, vTPM, integrity monitoring and standard non-Spot
scheduling.

It intentionally contains no application-service knowledge. It does not
install Docker, read secrets, initialize databases or start PostgreSQL,
message brokers, caches, reverse proxies or application containers.

```hcl
module "vm" {
  source = "./modules/vm"

  project_id           = var.project_id
  region               = var.region
  zone                 = var.zone
  name                 = "oilscope-dev-history"
  machine_type         = "e2-micro"
  subnetwork_id        = module.network.workload_subnet.id
  internal_ip          = "10.10.1.11"
  network_tags         = [module.network.network_tags.history]
  service_account_email = google_service_account.workload["history"].email
  boot_image            = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
  boot_disk_size_gb     = 20
  boot_disk_type        = "pd-balanced"
}
```
