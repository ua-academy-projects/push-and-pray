module "vm" {
  source = "../gcp-vm"

  vms = local.bastions
}
