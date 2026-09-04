# AWS stack module

This module owns the complete AWS stack. Its nested `config` module interprets
the shared JSON and resolves AWS profiles; `network` and `vm` contain the
provider resources. Nothing outside `modules/aws` contains AWS implementation
details.

If no VM selects AWS, the module creates no resources and returns empty maps.
No VPN, peering or cross-cloud route is created. Private workloads require an
AWS bastion for Ansible access.
