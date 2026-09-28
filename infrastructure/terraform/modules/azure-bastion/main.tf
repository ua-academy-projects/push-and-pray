module "vm" {
  source = "../azure-vm"

  resource_group_name = var.resource_group_name
  vms                 = local.bastions
}
