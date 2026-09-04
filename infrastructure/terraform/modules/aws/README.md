# AWS stack module

This module reads the shared project configuration, selects VMs whose effective
cloud is aws, resolves abstract profiles through clouds.aws dictionaries, and
owns AWS networking, EC2, IAM and SSM access policy resources.

If no VM selects AWS, the module creates no resources and returns empty maps.
No VPN, peering or cross-cloud route is created. Private workloads require an
AWS bastion for Ansible access.
