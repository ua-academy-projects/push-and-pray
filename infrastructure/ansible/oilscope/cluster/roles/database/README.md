# Database

Runs the application's PostgreSQL inside k3s as a CloudNativePG `Cluster`,
then applies the schema migrations with a Job. The operator itself comes from
the `cloudnative_pg` role, which has to run first.

## What it creates

| Resource | Purpose |
| --- | --- |
| `ImageCatalog/oilscope-db` | The image and its PostgreSQL major version (`database_pg_major`) |
| `Cluster/oilscope-db` | `database_instances` PostgreSQL pods: one primary, the rest streaming replicas |
| `Job/oilscope-db-migrate-<image>` | Runs every file of `database/migrations` against the primary, as the owner |

From the `Cluster`, CloudNativePG creates on its own:

| Resource | Use |
| --- | --- |
| `Service/oilscope-db-rw` | The primary - writes and reads |
| `Service/oilscope-db-ro` | The replicas - reads only |
| `Secret/oilscope-db-app` | `username`, `password`, `host`, `dbname`, `uri` of the owner; the application reads it |
| one PVC per instance | On k3s's local-path storage, so tied to the node the instance runs on |

## The image

`infrastructure/docker/Dockerfile.postgres`: the operator's own image
(`ghcr.io/cloudnative-pg/postgresql:17-standard-trixie`) plus the two
extensions the application needs and it lacks.

| Extension | Where it comes from |
| --- | --- |
| `hstore`, `pgcrypto` | PostgreSQL itself |
| `pg_cron` | `postgresql-17-cron` from the PostgreSQL apt repository |
| `pgmq` | Not packaged there; it is pure SQL, so its control file and script are copied from the pgmq release |

The migrations and `petroscope-migrate` are in the same image, which is what
the Job runs.

The `Cluster` names the image through an `ImageCatalog` rather than
`imageName`. With `imageName`, CloudNativePG reads the PostgreSQL major
version from the start of the tag (`17`, `17.6-...`); our tags are commit
SHAs, and from `0123456789abc...` it read major version 123456789. The
catalog states `major: 17` outright, and the operator trusts it instead of
guessing. Keep `database_pg_major` equal to `PG_MAJOR` in the Dockerfile.

## Who creates which extension

The owner (`oil_tracker`) is a plain role, not a superuser - the migrations
run as it, the application connects as it. Tested against the image:

| Extension | Created by | Why |
| --- | --- | --- |
| `pg_cron` | the superuser, in `postInitApplicationSQL` | not a trusted extension |
| `hstore`, `pgcrypto` | the owner, in the migrations | trusted extensions |
| `pgmq` | the owner, in the migrations | `superuser = false`, and the owner then owns the queue tables it creates |

`postInitApplicationSQL` also grants the owner `USAGE` on the `cron` schema -
migration 003 schedules the session cleanup job - and `pg_read_all_settings`,
because migration 003 reads `shared_preload_libraries`, which a plain role
may not. It runs once, when the cluster is first created: changing it later
does nothing to an existing cluster.

`pg_cron` has to be preloaded (`shared_preload_libraries`) and told which
database it serves (`cron.database_name`); CloudNativePG allows both.

## Placement

All instances run on nodes labelled `cloud=<database.cloud>`, each on a node
of its own (`podAntiAffinityType: required`): replication stays inside one
cloud instead of crossing the bastions, and losing a node loses at most one
copy of the data. That cloud therefore needs at least `database.instances`
nodes; the role checks it before creating anything.

## Configuration

| From the configuration | Role variable |
| --- | --- |
| `database.cloud` | `database_cloud` |
| `database.instances` | `database_instances` |
| `database.storage_gb` | `database_storage_gb` |
| `registry.repository` + `registry.image_sha` | `database_image` (`<repository>/postgres:<sha>`) |

Only the parameters the cluster needs are set: `cron.database_name`. Write-ahead
logging, replication and checkpoints keep CloudNativePG's and PostgreSQL's
defaults.

## Idempotency

`kubernetes.core.k8s` compares the manifest with what the cluster holds and
changes nothing when they match. The migrations Job is named after the image,
so the same image finds its Job already there and runs nothing; a new image
gets a new Job. Finished Jobs are kept rather than expired, for the same
reason: an expired Job would be created and run again on every deployment.

## Metrics

Every instance serves Prometheus metrics on port 9187 already. Scraping them
needs a `PodMonitor`, a resource type the Prometheus stage installs; switch
on `monitoring.enablePodMonitor` in the `Cluster` then.

## License

GPL-2.0-or-later
