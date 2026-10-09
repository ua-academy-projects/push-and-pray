# Tailscale

Installs Tailscale and joins the host to the tailnet as a subnet router: it
advertises the ranges given to it and forwards traffic between them and the
rest of the tailnet. The project runs it on every bastion, one per cloud, each
advertising its own cloud's `network_cidr`.

## What it does

1. Adds Tailscale's apt repository for the host's Ubuntu release and installs
   the package - once, or at exactly `tailscale_version` when one is set.
2. Turns on IP forwarding in the kernel (`/etc/sysctl.d/99-tailscale.conf`).
3. Sets the port tailscaled listens on in `/etc/default/tailscaled` and
   restarts the daemon when it changes.
4. Reads the device's state (`tailscale status --json`) and settings
   (`tailscale debug prefs`) and compares them with the variables:
   - not logged in, or other tags: logs in with `tailscale up` and the auth key;
   - logged in, other settings: applies them with `tailscale set`;
   - otherwise does nothing.
5. Checks the device is connected, and says so when the tailnet has not
   approved the advertised routes yet.

A second run on an unchanged host reports `changed=0`.

## Why it is built this way

- **Comparing settings, not skipping steps.** The login is not guarded by
  `creates` or "already logged in": a changed route, flag or tag is applied on
  the next run. Tags are bound to the login itself - `tailscale set` cannot
  change them - so new tags mean logging in again.
- **The auth key never becomes an argument.** It is written to a file in
  `/run` (memory), passed as `--auth-key=file:<path>`, and removed in an
  `always` block, so it is not in `ps`, a shell history or on disk. The task
  writing it is `no_log`.
- **No SNAT.** `--snat-subnet-routes=false` keeps the source address of
  forwarded traffic. Across clouds a node sees the real address of the node
  that spoke to it, and the cloud firewalls admit the other clouds and the
  tailnet by range - written for exactly that. The price is a route back:
  every cloud routes the tailnet range to its bastion (Terraform's `routing`
  modules).
- **`--accept-dns=false`.** A cloud VM resolves through its provider's metadata
  DNS; letting the tailnet replace the resolver would break that on the host
  every other node depends on.
- **`--reset` on login.** Flags not named by the role return to their defaults,
  so nothing set by hand survives a login.

## Requirements

- Ubuntu, with privilege escalation.
- The `ansible.posix` collection on the controller.
- An auth key for the first login. Generate it as **reusable**, **ephemeral**
  (a destroyed VM leaves the device list on its own) and **pre-authorized**,
  with the tags in `tailscale_advertise_tags`. An ephemeral device that stays
  offline is removed from the tailnet; the next run logs it in again, so the
  key has to be valid then too.
- In the tailnet policy, the tags owned by someone, and listed under
  `autoApprovers.routes` for the advertised ranges - otherwise approve them by
  hand in the admin console.

## Variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `tailscale_version` | `""` | apt version to pin; empty installs once and never upgrades |
| `tailscale_apt_suite` | host's codename | Release the repository is read for |
| `tailscale_port` | `41641` | UDP port for direct connections; the cloud firewall opens the same one |
| `tailscale_auth_key` | `""` | Needed only to log in |
| `tailscale_hostname` | `inventory_hostname` | Device name in the tailnet |
| `tailscale_advertise_routes` | `[]` | Ranges this device routes for the tailnet |
| `tailscale_advertise_tags` | `[]` | Tags to log in with |
| `tailscale_accept_routes` | `false` | Use routes other routers advertise |
| `tailscale_snat_subnet_routes` | `false` | Rewrite the source of forwarded traffic |
| `tailscale_accept_dns` | `false` | Let the tailnet's DNS replace the host's |

In this project the bastion's values come from the configuration through
`inventory/group_vars/bastion.yml`: the port and tags from `tailscale`, the
route from `clouds.<cloud>.network_cidr`, and `accept_routes` turned on when
nodes run in more than one cloud.

## Usage

The project's playbook, `oilscope.cluster.tailscale_routers`, reads the key
where it is kept: in the secret store, as `TAILSCALE_AUTHKEY`, through
`resolve_secrets` on a `k3s_server` node - the only hosts allowed to read it -
and hands it to the bastions in memory:

```yaml
- name: Read the Tailscale auth key on a server
  hosts: k3s_server[0]
  vars:
    oilscope_nodes_via_bastion: true
  roles:
    - role: oilscope.cluster.resolve_secrets

- name: Turn every bastion into its cloud's subnet router
  hosts: bastion
  become: true
  roles:
    - role: oilscope.cluster.tailscale
      vars:
        tailscale_auth_key: >-
          {{ hostvars[groups['k3s_server'][0]].resolve_secrets_result.TAILSCALE_AUTHKEY }}
```

The server is reached through its cloud's bastion rather than the tailnet,
because on a fresh environment the tailnet is what this play builds.

## License

GPL-2.0-or-later
