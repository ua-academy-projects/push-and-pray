from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
STACKS = {
    "ui-vm": {
        "env": "AEGIS_UI_ENV_FILE",
        "services": {
            "ui": ("aegis-ui", ["uvicorn", "ui_service.main:app"], True),
        },
    },
    "history-vm": {
        "env": "AEGIS_HISTORY_ENV_FILE",
        "services": {
            "history-api": (
                "aegis-history-api",
                ["uvicorn", "history_service.main:app"],
                True,
            ),
            "history-consumer": (
                "aegis-history-consumer",
                ["aegis-history-blacklist-consumer"],
                False,
            ),
        },
    },
    "provider-vm": {
        "env": "AEGIS_PROVIDER_ENV_FILE",
        "services": {
            "provider-api": (
                "aegis-provider-api",
                ["uvicorn", "provider_service.main:app"],
                True,
            ),
            "provider-worker": (
                "aegis-provider-worker",
                ["aegis-provider-blacklist-worker"],
                False,
            ),
        },
    },
}


def _compose_command() -> list[str]:
    if executable := shutil.which("docker-compose"):
        return [executable]
    if executable := shutil.which("docker"):
        result = subprocess.run(
            [executable, "compose", "version"],
            capture_output=True,
            check=False,
            text=True,
        )
        if result.returncode == 0:
            return [executable, "compose"]
    pytest.skip("Docker Compose is not installed")


@pytest.mark.parametrize(("vm", "stack"), STACKS.items())
def test_compose_defines_isolated_production_runtimes(
    vm: str,
    stack: dict[str, object],
    tmp_path: Path,
) -> None:
    compose_file = REPOSITORY_ROOT / "deploy" / vm / "compose.yaml"
    env = os.environ.copy()
    env[str(stack["env"])] = str(
        REPOSITORY_ROOT
        / "services"
        / f"{vm.removesuffix('-vm')}-service"
        / ".env.example"
    )
    env["XDG_CACHE_HOME"] = str(tmp_path / "cache")
    result = subprocess.run(
        [*_compose_command(), "-f", str(compose_file), "config", "--format", "json"],
        capture_output=True,
        check=False,
        env=env,
        text=True,
    )
    assert result.returncode == 0, result.stderr

    services = json.loads(result.stdout)["services"]
    expected_services = stack["services"]
    assert set(services) == set(expected_services)

    for service_name, (
        container_name,
        command_prefix,
        publishes_port,
    ) in expected_services.items():
        service = services[service_name]
        assert service["container_name"] == container_name
        assert service["command"][: len(command_prefix)] == command_prefix
        assert "--reload" not in service["command"]
        assert service["restart"] == "unless-stopped"
        assert service["read_only"] is True
        assert service["init"] is True
        assert service["healthcheck"]["test"]
        assert bool(service.get("ports")) is publishes_port


@pytest.mark.parametrize("service", ["ui", "history", "provider"])
def test_application_images_use_non_root_runtime_and_small_context(
    service: str,
) -> None:
    service_root = REPOSITORY_ROOT / "services" / f"{service}-service"
    dockerfile = (service_root / "Dockerfile").read_text()
    dockerignore = (service_root / ".dockerignore").read_text().splitlines()

    assert dockerfile.count("FROM python:3.14-slim") == 2
    assert "USER 10001:10001" in dockerfile
    assert "pip install --no-cache-dir" in dockerfile
    assert all(
        secret not in dockerfile
        for secret in ("ABUSEIPDB_API_KEY", "MARIADB_PASSWORD", "RABBITMQ_PASSWORD")
    )
    assert {".env", ".git", ".venv", "tests"}.issubset(dockerignore)


def test_provisioning_does_not_start_python_on_vm_hosts() -> None:
    for vm in ("ui", "history", "provider"):
        script = (REPOSITORY_ROOT / "provision" / f"{vm}-vm.sh").read_text()
        assert "ExecStart=" not in script
        assert ".venv/bin/" not in script
        assert "docker compose" in script


def test_infrastructure_compose_defines_only_required_private_services(
    tmp_path: Path,
) -> None:
    compose_file = REPOSITORY_ROOT / "deploy" / "infra-vm" / "compose.yaml"
    env_file = tmp_path / "infra.env"
    definitions_file = tmp_path / "definitions.json"
    acl_file = tmp_path / "users.acl"
    env_file.write_text(
        "MARIADB_DATABASE=aegis_history\n"
        "MARIADB_USER=aegis_history\n"
        "MARIADB_PASSWORD=example-app-password\n"
        "MARIADB_ROOT_PASSWORD=example-root-password\n"
    )
    definitions_file.write_text("{}\n")
    acl_file.write_text("user default off\n")
    env = {
        **os.environ,
        "AEGIS_INFRA_ENV_FILE": str(env_file),
        "AEGIS_RABBITMQ_DEFINITIONS_FILE": str(definitions_file),
        "AEGIS_REDIS_ACL_FILE": str(acl_file),
        "XDG_CACHE_HOME": str(tmp_path / "cache"),
    }
    result = subprocess.run(
        [*_compose_command(), "-f", str(compose_file), "config", "--format", "json"],
        capture_output=True,
        check=False,
        env=env,
        text=True,
    )
    assert result.returncode == 0, result.stderr

    config = json.loads(result.stdout)
    services = config["services"]
    assert set(services) == {"mariadb", "rabbitmq", "redis"}
    assert {service["container_name"] for service in services.values()} == {
        "aegis-mariadb",
        "aegis-rabbitmq",
        "aegis-redis",
    }
    assert all(service["restart"] == "unless-stopped" for service in services.values())
    assert all(service["healthcheck"]["test"] for service in services.values())
    assert "management" in services["rabbitmq"]["image"]
    assert set(config["volumes"]) == {
        "mariadb-data",
        "rabbitmq-data",
        "redis-data",
    }

    published = {
        port["published"]: port["host_ip"]
        for service in services.values()
        for port in service["ports"]
    }
    assert published == {
        "3306": "192.168.100.14",
        "5672": "192.168.100.14",
        "6379": "192.168.100.14",
        "15672": "192.168.100.14",
    }


def test_local_compose_preserves_service_boundaries_and_private_dependencies(
    tmp_path: Path,
) -> None:
    compose_file = REPOSITORY_ROOT / "deploy" / "local" / "compose.yaml"
    env_file = REPOSITORY_ROOT / "deploy" / "local" / ".env.example"
    env = {**os.environ, "XDG_CACHE_HOME": str(tmp_path / "cache")}
    result = subprocess.run(
        [
            *_compose_command(),
            "--env-file",
            str(env_file),
            "-f",
            str(compose_file),
            "config",
            "--format",
            "json",
        ],
        capture_output=True,
        check=False,
        env=env,
        text=True,
    )
    assert result.returncode == 0, result.stderr

    config = json.loads(result.stdout)
    services = config["services"]
    assert set(services) == {
        "mariadb",
        "rabbitmq",
        "redis",
        "history-migrate",
        "history-api",
        "history-consumer",
        "provider-api",
        "provider-worker",
        "ui",
    }
    assert set(config["volumes"]) == {
        "mariadb-data",
        "rabbitmq-data",
        "redis-data",
    }
    assert all(
        set(service["networks"]) == {"aegis-private"} for service in services.values()
    )

    assert services["history-api"]["environment"]["MARIADB_HOST"] == "mariadb"
    assert services["history-api"]["environment"]["PROVIDER_SERVICE_URL"] == (
        "http://provider-api:8001"
    )
    assert services["history-consumer"]["environment"]["RABBITMQ_HOST"] == "rabbitmq"
    assert services["provider-worker"]["environment"]["RABBITMQ_HOST"] == "rabbitmq"
    assert services["ui"]["environment"]["HISTORY_SERVICE_URL"] == (
        "http://history-api:8002"
    )
    assert services["ui"]["environment"]["REDIS_HOST"] == "redis"

    published = {
        (port["published"], port["target"], port["host_ip"])
        for service in services.values()
        for port in service.get("ports", [])
    }
    assert published == {
        ("8000", 8000, "127.0.0.1"),
        ("8001", 8001, "127.0.0.1"),
        ("8002", 8002, "127.0.0.1"),
        ("15672", 15672, "127.0.0.1"),
    }
    assert services["history-migrate"]["restart"] == "no"
    assert services["history-api"]["depends_on"]["history-migrate"]["condition"] == (
        "service_completed_successfully"
    )
    assert (
        services["history-consumer"]["depends_on"]["history-migrate"]["condition"]
        == "service_completed_successfully"
    )


def test_vagrant_topology_has_no_separate_database_vm() -> None:
    vagrantfile = (REPOSITORY_ROOT / "Vagrantfile").read_text()
    assert '"db-vm"' not in vagrantfile
    assert "provision/db-vm.sh" not in vagrantfile


def test_vagrant_is_native_windows_virtualbox_compatible() -> None:
    vagrantfile = (REPOSITORY_ROOT / "Vagrantfile").read_text()

    assert 'type: "virtualbox"' in vagrantfile
    assert '"/vagrant"' in vagrantfile
    assert "virtualbox.gui = false" in vagrantfile
    assert "trigger.run" not in vagrantfile
    assert "bash provision/" not in vagrantfile
    assert set(
        match
        for match in ("ui-vm", "history-vm", "provider-vm", "infra-vm")
        if f'"{match}" =>' in vagrantfile
    ) == {"ui-vm", "history-vm", "provider-vm", "infra-vm"}


def test_windows_secret_initializer_and_documented_lifecycle_exist() -> None:
    initializer = (
        REPOSITORY_ROOT / "scripts" / "Initialize-AegisVagrant.ps1"
    ).read_text()
    documentation = (REPOSITORY_ROOT / "docs" / "development-vagrant.md").read_text()

    assert "RandomNumberGenerator" in initializer
    assert "Read-Host" in initializer
    assert "WSL" in documentation
    for command in (
        "vagrant validate",
        "vagrant up",
        "vagrant status",
        "vagrant ssh",
        "vagrant provision <vm>",
        "vagrant reload <vm>",
        "vagrant halt",
        "vagrant destroy -f",
    ):
        assert command in documentation


def test_windows_checkout_preserves_guest_script_line_endings() -> None:
    attributes = (REPOSITORY_ROOT / ".gitattributes").read_text()

    assert "*.sh text eol=lf" in attributes
    assert "Vagrantfile text eol=lf" in attributes
    assert "*.yaml text eol=lf" in attributes
    assert "*.ps1 text eol=crlf" in attributes


def test_history_waits_for_infrastructure_before_migrations() -> None:
    script = (REPOSITORY_ROOT / "provision" / "history-vm.sh").read_text()

    mariadb_wait = script.index(
        'wait_for_tcp "${DATABASE_ADDRESS}" "${DATABASE_PORT}" MariaDB'
    )
    rabbitmq_wait = script.index('wait_for_tcp "${RABBITMQ_ADDRESS}" 5672 RabbitMQ')
    migration = script.index("history-api alembic")
    startup = script.index("up --detach --remove-orphans")
    assert mariadb_wait < migration < startup
    assert rabbitmq_wait < migration
