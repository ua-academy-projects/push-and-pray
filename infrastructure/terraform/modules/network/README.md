# GCP network

Owns the VPC, management/workload subnets, Cloud Router, and Cloud NAT. The
historical `module.network[0]` address is retained to preserve live network
state. Inputs are the resource prefix, provider region, and structured network
configuration. Outputs are the network and subnet IDs.

Application ingress policy belongs to `modules/gcp_firewall`. Five root moved
blocks preserve the existing firewall rules during extraction. Workload SSH
accepts traffic only from the bastion tag. Public bastion SSH uses its final
configured port; there is no temporary port-22 rule.
