# Bastion NAT role

Configures an AWS bastion as the NAT instance for the private workload subnet.
Terraform remains responsible for disabling EC2 source/destination checks and
for routing `0.0.0.0/0` to the bastion network interface. This role enables
IPv4 forwarding and installs a persistent nftables masquerade rule inside the
guest OS.
