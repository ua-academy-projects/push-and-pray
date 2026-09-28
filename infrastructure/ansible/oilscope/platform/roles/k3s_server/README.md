# K3s server role

Installs the K3s version pinned in the project configuration and either creates
the first embedded-etcd server or joins another server through the first
server's private address. GCP passthrough load-balancer backend VMs cannot use
their own VIP as an initial join endpoint because traffic loops back to the
originating backend. Shared critical cluster settings are rendered identically
on every server. The role labels and taints server nodes as control-plane nodes.

This role is orchestrated by `oilscope.platform.k3s`; it expects
`oilscope.platform.k3s_common` and `oilscope.platform.resolve_secrets` to have
run first.
