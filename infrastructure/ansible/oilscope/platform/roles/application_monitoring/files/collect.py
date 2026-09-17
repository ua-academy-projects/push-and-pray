#!/usr/bin/env python3
"""Read-only workload diagnostics. No cloud SDKs or application credentials needed."""

import datetime as dt
import json
import math
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

EXPECTED_INSTRUMENTS = {"WTI_USD_BBL", "BRENT_USD_BBL", "RBOB_GASOLINE_USD_GAL"}


def request_json(url, headers=None, data=None):
    if urllib.parse.urlsplit(url).scheme not in {"http", "https"}:
        raise ValueError("Only HTTP(S) diagnostics are supported")
    request = urllib.request.Request(url, headers=headers or {}, data=data)  # noqa: S310
    try:
        with urllib.request.urlopen(request, timeout=10) as response:  # noqa: S310
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        # Health endpoints expose useful diagnostics even on a 503.
        return error.code, json.load(error)


def command(*args):
    # Callers provide fixed executables/arguments; shell expansion is never enabled.
    return subprocess.run(  # noqa: S603
        args, capture_output=True, text=True, check=True, timeout=15
    ).stdout


def container(project, service):
    ids = command(
        "docker",
        "ps",
        "--filter",
        f"label=com.docker.compose.project={project}",
        "--filter",
        f"label=com.docker.compose.service={service}",
        "--format",
        "{{.ID}}",
    ).split()
    if len(ids) != 1:
        raise ValueError("Expected exactly one running service container")
    return ids[0]


def freshness(rows, now):
    latest = {row["instrument_code"]: row for row in rows}
    if not EXPECTED_INSTRUMENTS.issubset(latest):
        raise ValueError("Missing instrument observations")
    ages = []
    for code in EXPECTED_INSTRUMENTS:
        observed = dt.datetime.fromisoformat(latest[code]["fetched_at"].replace("Z", "+00:00"))
        if observed.tzinfo is None:
            raise ValueError("Observation needs timezone")
        age = now - observed.timestamp()
        if age < -300:
            raise ValueError("Observation is in the future")
        ages.append(max(0, age))
    return max(ages)


def redis_metrics(info):
    fields = dict(
        line.split(":", 1) for line in info.splitlines() if ":" in line and not line.startswith("#")
    )
    limit = float(fields["maxmemory"])
    if limit <= 0:
        raise ValueError("Redis memory limit missing")
    return {
        "RedisMemoryPercent": float(fields["used_memory"]) / limit * 100,
        "RedisPersistenceFailed": int(
            fields["aof_enabled"] != "1"
            or fields["aof_last_write_status"] != "ok"
            or fields["aof_last_bgrewrite_status"] != "ok"
            or fields["rdb_last_bgsave_status"] != "ok"
        ),
    }


def queue_metrics(rows, queue):
    by_name = {row["name"]: row for row in rows}
    # All three queues are declared by the application's broker topology.
    if not {queue, queue + ".retry", queue + ".dead"}.issubset(by_name):
        raise ValueError("Broker topology incomplete")
    return {
        "RabbitReady": sum(
            int(by_name[name]["messages_ready"]) for name in (queue, queue + ".retry")
        ),
        "RabbitUnacked": sum(
            int(by_name[name]["messages_unacknowledged"]) for name in (queue, queue + ".retry")
        ),
        "RabbitDead": int(by_name[queue + ".dead"]["messages_ready"])
        + int(by_name[queue + ".dead"]["messages_unacknowledged"]),
    }


def collect(config):
    metrics = {"CollectionFailed": 0}
    failures = []

    def probe(name, function):
        try:
            metrics.update(function())
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
            metrics["CollectionFailed"] = 1
            failures.append(name)  # Never log commands, HTTP bodies or secret-bearing exceptions.

    role = config["role"]
    if role in ("history", "fetcher"):

        def health():
            port = config["history_port"] if role == "history" else 8002
            status, body = request_json(f"http://127.0.0.1:{port}/health")
            result = {"HealthFailed": int(status != 200 or body.get("status") != "ok")}
            if role == "fetcher":
                outbox = body["outbox"]
                result["OutboxPending"] = outbox["pending_count"]
                age = outbox["oldest_pending_seconds"]
                if result["OutboxPending"] and age is None:
                    raise ValueError("Missing oldest pending age")
                result["OutboxOldestSeconds"] = age or 0
            return result

        probe("health", health)
    if role == "history":

        def data_age():
            status, rows = request_json(
                f"http://127.0.0.1:{config['history_port']}/v1/observations/latest"
            )
            if status != 200:
                raise ValueError("History unavailable")
            return {"DataAgeSeconds": freshness(rows, time.time())}

        probe("freshness", data_age)

        def rabbit():
            cid = container("oilscope-rabbitmq", "rabbitmq")
            rows = json.loads(
                command(
                    "docker",
                    "exec",
                    cid,
                    "rabbitmqctl",
                    "list_queues",
                    "--vhost",
                    config["rabbitmq_vhost"],
                    "name",
                    "messages_ready",
                    "messages_unacknowledged",
                    "--formatter",
                    "json",
                )
            )
            return queue_metrics(rows, config["rabbitmq_queue"])

        probe("rabbitmq", rabbit)
    if role == "ui":

        def ui_health():
            cid = container("petroscope", "ui")
            # UI has no host port; run its existing Python HTTP client inside the container.
            command(
                "docker",
                "exec",
                cid,
                "python",
                "-c",
                "import urllib.request; "
                "urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=8).read()",
            )
            return {"HealthFailed": 0}

        probe("health", ui_health)

        def redis():
            cid = container("oilscope-redis", "redis")
            info = command(
                "docker",
                "exec",
                cid,
                "sh",
                "-c",
                'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli --no-auth-warning INFO',
            )
            return redis_metrics(info)

        probe("redis", redis)
    if role == "database":

        def postgres():
            cid = container("petroscope", "postgres")
            command(
                "docker",
                "exec",
                cid,
                "sh",
                "-c",
                'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"',
            )
            return {}

        probe("postgres", postgres)
    if "health" in failures:
        metrics["HealthFailed"] = 1
    if failures:
        print(json.dumps({"failed_probes": failures}), file=sys.stderr)
    if not all(
        isinstance(value, (int, float)) and math.isfinite(value) and value >= 0
        for value in metrics.values()
    ):
        raise ValueError("Invalid measurement")
    return metrics


def emf(config, metrics, timestamp):
    units = {
        "RedisMemoryPercent": "Percent",
        "OutboxOldestSeconds": "Seconds",
        "DataAgeSeconds": "Seconds",
    }
    return {
        "_aws": {
            "Timestamp": int(timestamp * 1000),
            "CloudWatchMetrics": [
                {
                    "Namespace": config["namespace"],
                    "Dimensions": [["VMKey"]],
                    "Metrics": [{"Name": key, "Unit": units.get(key, "Count")} for key in metrics],
                }
            ],
        },
        "VMKey": config["vm_key"],
        **metrics,
    }


def gcp_payload(config, metrics, timestamp):
    end = dt.datetime.fromtimestamp(timestamp, dt.UTC).isoformat().replace("+00:00", "Z")
    return {
        "timeSeries": [
            {
                "metric": {
                    "type": f"custom.googleapis.com/{config['name_prefix']}/{config['environment']}/{key}"
                },
                "resource": {
                    "type": "gce_instance",
                    "labels": {
                        "project_id": config["project_id"],
                        "instance_id": config["instance_id"],
                        "zone": config["zone"],
                    },
                },
                "metricKind": "GAUGE",
                "valueType": "DOUBLE",
                "points": [{"interval": {"endTime": end}, "value": {"doubleValue": float(value)}}],
            }
            for key, value in metrics.items()
        ]
    }


def publish(config, metrics):
    now = time.time()
    if config["cloud"] == "aws":
        with Path("/var/log/oilscope/application-metrics.jsonl").open("a") as destination:
            destination.write(json.dumps(emf(config, metrics, now)) + "\n")
    elif config["cloud"] == "gcp":
        status, token = request_json(
            "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
            {"Metadata-Flavor": "Google"},
        )
        if status != 200:
            raise ValueError("Metadata token unavailable")
        status, _ = request_json(
            f"https://monitoring.googleapis.com/v3/projects/{config['project_id']}/timeSeries",
            {
                "Authorization": "Bearer " + token["access_token"],
                "Content-Type": "application/json",
            },
            json.dumps(gcp_payload(config, metrics, now)).encode(),
        )
        if status != 200:
            raise ValueError("Metrics publication failed")
    else:
        raise ValueError("Unsupported cloud")


def main():
    config = json.loads(Path(sys.argv[1]).read_text())
    publish(config, collect(config))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Collector failed: {type(error).__name__}", file=sys.stderr)
        sys.exit(1)
