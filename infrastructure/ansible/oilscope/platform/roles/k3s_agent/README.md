# K3s agent role

Installs the K3s version pinned in the project configuration and joins a worker
agent through the private API load balancer. The role labels the node with
`oilscope.io/role=agent`.

This role is orchestrated by `oilscope.platform.k3s`; it expects
`oilscope.platform.k3s_common` and `oilscope.platform.resolve_secrets` to have
run first.
