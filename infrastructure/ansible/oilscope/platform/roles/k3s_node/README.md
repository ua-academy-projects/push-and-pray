# k3s_node

Installs a pinned K3s release and writes `/etc/rancher/k3s/config.yaml`.
The same role initializes the first embedded-etcd server, joins additional
control-plane servers, and joins worker agents. Join tokens are marked
`no_log` by the calling playbook.
