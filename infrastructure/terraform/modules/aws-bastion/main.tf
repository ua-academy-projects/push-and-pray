module "vm" {
  source = "../aws-vm"

  vms = local.bastions
}
