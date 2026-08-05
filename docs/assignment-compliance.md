# Current architecture compliance

| Requirement | Status | Evidence |
|---|---|---|
| Preserve five application VMs | Implemented in configuration | `Vagrantfile` retains all five application machines |
| Dedicated log database VM | Implemented in configuration | Sixth `logs` VM runs Loki/Grafana behind TLS Nginx |
| Independent Compose per VM | Implemented in configuration | `infra/docker/<role>/compose.yml` |
| No native application systemd services | Implemented in provisioners | Provisioners disable old units and start Compose |
| UI reads History Service | Implemented | Nginx `/api/v1/` targets History Service |
| API Fetcher only collects/publishes | Implemented | Python has providers and RabbitMQ, no database config |
| History consumes MQ and owns DB | Implemented | Go consumer inserts with `pgx` |
| No HTTP write fallback | Implemented | Observation writes use `rates.events` only |
| Durable delivery and DLQ | Implemented in code | Both event and command topology are durable |
| Database persists outside container and VM root disk | Implemented in configuration | Bind-backed volume on `.vagrant-data/database/postgresql.qcow2` |
| Empty DB initial backfill | Implemented | Startup planner uses a maximum 365-day range |
| Existing DB incremental backfill | Implemented | Latest timestamp is calculated per instrument |
| Runtime six-VM proof | Not yet verified in this change | Requires privileged QEMU/vmnet/network execution |

Static validation must be reported separately from runtime proof.
