# technitium

Installs one private Technitium DNS Server in K3s.

The role:

- deploys the pinned official image as a StatefulSet;
- persists `/etc/dns` on a `local-path` volume;
- exposes DNS on TCP/UDP 53 and the console on 5380 through ClusterIP only;
- allows recursive queries only from private and Tailscale address ranges;
- generates the administrator credentials inside Kubernetes;
- creates a separate Homepage API user and token;
- copies only that API token into the Homepage namespace;
- configures K3s CoreDNS to forward external lookups to Technitium.

The role does not replace K3s CoreDNS or public Cloudflare DNS. Pods continue
to query CoreDNS: Kubernetes service names are resolved locally, while all
other names are forwarded to the private Technitium Service.

Access the private console from the K3s bootstrap server:

```bash
sudo k3s kubectl -n technitium port-forward service/technitium 4469:5380
```

Then forward port `4469` through SSH and open `http://127.0.0.1:4469`.
