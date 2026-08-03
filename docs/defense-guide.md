# Rateboard defense guide

## Short explanation

> Rateboard uses five Vagrant VMs with a separate Docker Compose project on
> each VM. API Fetcher only calls providers and publishes normalized events to
> RabbitMQ. History Service consumes those events, owns PostgreSQL, and serves
> all UI reads.

## Why the boundaries matter

1. UI has no provider, queue, or database credentials.
2. API Fetcher can change provider-specific code without changing UI or schema.
3. RabbitMQ separates provider availability from database writes.
4. History Service is the single database owner.
5. PostgreSQL remains the durable source of current and historical observations.

## Main flow

```text
Provider -> API Fetcher -> RabbitMQ -> History Service -> PostgreSQL
Browser  -> UI ----------------------> History Service -> PostgreSQL
```

RabbitMQ is not queried for charts. It only transports commands and observation
events.

## Typical questions

1. **Why does UI not call API Fetcher?** API Fetcher is a collector/producer,
   while History Service owns the stable read contract.
2. **When is a message saved?** Publisher confirmation means queued. It is saved
   only after History Service commits it and ACKs the delivery.
3. **What happens on duplicate delivery?** PostgreSQL uniqueness and
   `ON CONFLICT DO NOTHING` make processing idempotent.
4. **How does startup backfill work?** History Service checks the latest
   timestamp per instrument and publishes bounded fetch commands.
5. **What happens with a new database?** Migrations run, then every missing
   instrument receives an initial command for at most 365 days.
6. **How is the database preserved?** Its Docker volume binds to an ext4
   filesystem on a host-side qcow2 disk under `.vagrant-data/database`.
7. **Why are there five Compose files?** Docker networks do not span independent
   VM daemons; each VM owns its workload and cross-VM traffic uses the LAN.
8. **Why is systemd still present for Docker?** It manages the Docker daemon,
   not Rateboard application services.

## Verification wording

Passing unit tests, shell syntax, and `Vagrantfile` parsing are static evidence.
Runtime proof requires five running VMs, healthy Compose containers, queue
inspection, database ranges, and an observation visible through History API.
