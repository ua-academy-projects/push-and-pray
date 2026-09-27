# GCP network

Creates the VPC, management/workload subnets, Cloud Router and Cloud NAT from
the project JSON. Creates no resources when no VM selects GCP.

Outputs `network_id` and `subnet_ids` are passed by the root to sibling
security and VM modules. Firewall rules live in `../gcp-security`.
