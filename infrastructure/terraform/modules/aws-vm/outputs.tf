output "public_ips" {
  description = "Static public IP addresses keyed by logical VM name."
  value = {
    for name, address in aws_eip.public : name => address.public_ip
  }
}

output "instance_ids" {
  description = "EC2 instance IDs keyed by logical VM name."
  value = {
    for name, instance in aws_instance.this : name => instance.id
  }
}

output "volume_ids" {
  description = "EBS volume IDs keyed by logical VM and disk name."
  value = {
    for name, instance in aws_instance.this : name => merge(
      { root = instance.root_block_device[0].volume_id },
      {
        for disk_name, disk in local.vms[name].data_disks :
        disk_name => one([
          for attached_disk in instance.ebs_block_device : attached_disk.volume_id
          if attached_disk.device_name == disk.device_name
        ])
      },
    )
  }
}
