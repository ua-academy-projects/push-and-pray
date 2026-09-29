# K3s common role

Prepares every K3s server and agent by installing host prerequisites, disabling
swap, loading the required kernel modules, applying forwarding sysctls, and
downloading the official K3s installer from the release tag selected by
`k3s.version`. Pinning the installer source avoids depending on the mutable
`get.k3s.io` endpoint; the installer then downloads and verifies the matching
K3s release binary. The role also retrieves the shared `K3S_TOKEN` supplied by
the `resolve_secrets` role without logging it.

This role is orchestrated by `oilscope.platform.k3s`; it is not intended to be
run by itself.
