# homepage

Installs Homepage through the K3s Helm controller and configures it as a
private operations dashboard for OilScope.

The dashboard displays:

- K3s cluster and node CPU/memory information;
- OilScope UI, History and Fetcher workloads;
- CloudNativePG, RabbitMQ and Redis workloads;
- private Technitium DNS statistics when Technitium is enabled;
- links to the public application and private Headlamp dashboard.

The Service remains private:

- its type is `ClusterIP`;
- no Ingress or public load balancer is created;
- Kubernetes access uses a read-only ServiceAccount;
- access is provided through SSH and `kubectl port-forward`.

From the K3s bootstrap server:

```bash
sudo k3s kubectl -n homepage port-forward service/homepage 4468:3000
```

Forward local port `4468` through SSH to that server and open:

```text
http://127.0.0.1:4468
```

The Helm chart is the community chart recommended by Homepage's official
Kubernetes documentation. The application image is pinned separately.
