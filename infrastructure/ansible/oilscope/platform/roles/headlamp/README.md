# headlamp

Installs the official Headlamp Helm chart through the K3s Helm controller.

The dashboard is private by design:

- its Service type is `ClusterIP`;
- no Ingress or public load balancer is created;
- the Headlamp ServiceAccount receives the built-in read-only `view` role;
- no long-lived login token is stored in the repository or cluster manifests.

Run these commands on the K3s bootstrap server to access it:

```bash
sudo k3s kubectl -n headlamp create token headlamp
sudo k3s kubectl -n headlamp port-forward service/headlamp 8080:80
```

Forward port `8080` from your computer through SSH, open
`http://127.0.0.1:8080`, and paste the generated token into Headlamp.
