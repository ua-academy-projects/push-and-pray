from __future__ import annotations

import json
from pathlib import Path

import pytest
from scripts.terraform_init import (
    PreflightError,
    build_init_command,
    read_backend_settings,
    validate_project_config,
)

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = REPOSITORY_ROOT / "infrastructure" / "terraform" / "project-config.schema.json"


def synthetic_project_config() -> dict[str, object]:
    return {
        "config_version": 3,
        "project_id": "example-project-12345",
        "environment": "dev",
        "region": "us-central1",
        "zone": "us-central1-a",
        "name_prefix": "oilscope",
        "common_labels": {},
        "terraform": {
            "backend": {
                "bucket": "example-project-12345-tfstate",
                "prefix": "oilscope/dev",
            }
        },
        "registry": {
            "repository": "ghcr.io/example-org/example-project",
            "image_sha": "0123456789abcdef0123456789abcdef01234567",
        },
        "network": {
            "management_subnet_cidr": "10.0.0.0/29",
            "workload_subnet_cidr": "10.0.1.0/26",
            "ui_public_ports": [80, 443],
        },
        "service_ports": {
            "history_api": 8001,
            "postgresql": 5432,
        },
        "vms": {
            "bastion": {
                "role": "bastion",
                "machine_type": "e2-micro",
                "image": ("projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"),
                "internal_ip": "10.0.0.2",
                "boot_disk": {
                    "size_gb": 10,
                    "type": "pd-balanced",
                },
                "assign_public_ip": True,
                "network_tags": ["bastion"],
                "automation_role": "none",
                "secret_mappings": {},
                "ssh_port": 8787,
                "allowed_cidrs": ["192.0.2.10/32"],
                "preemptible": False,
            },
            "infra": {
                "role": "database",
                "machine_type": "e2-micro",
                "image": ("projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"),
                "internal_ip": "10.0.1.2",
                "boot_disk": {
                    "size_gb": 10,
                    "type": "pd-balanced",
                },
                "assign_public_ip": False,
                "network_tags": ["infra"],
                "automation_role": "database",
                "secret_mappings": {
                    "POSTGRES_PASSWORD": "example-db-password",
                },
                "preemptible": False,
            },
        },
    }


def write_synthetic_config(tmp_path: Path) -> Path:
    config_path = tmp_path / "synthetic-project.json"
    config_path.write_text(json.dumps(synthetic_project_config()), encoding="utf-8")
    return config_path


def test_synthetic_project_configuration_matches_schema(tmp_path: Path) -> None:
    config = validate_project_config(write_synthetic_config(tmp_path), SCHEMA_PATH)
    assert read_backend_settings(config) == (
        "example-project-12345-tfstate",
        "oilscope/dev",
    )


def test_tracked_example_configuration_matches_schema() -> None:
    config = validate_project_config(
        REPOSITORY_ROOT / "project-config.example.json",
        SCHEMA_PATH,
    )

    assert config["config_version"] == 3
    assert config["registry"]["image_sha"] == ("0123456789abcdef0123456789abcdef01234567")
    assert config["vms"]["bastion"]["role"] == "bastion"


def test_schema_rejects_legacy_root_bastion_configuration(tmp_path: Path) -> None:
    config = synthetic_project_config()
    config["bastion"] = config["vms"].pop("bastion")
    config_path = tmp_path / "legacy-bastion.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")

    with pytest.raises(PreflightError, match="failed JSON Schema"):
        validate_project_config(config_path, SCHEMA_PATH)


def test_backend_rejects_secret_or_credentials_fields() -> None:
    config = {
        "terraform": {
            "backend": {
                "bucket": "safe-state-bucket",
                "prefix": "oilscope/dev",
                "credentials": "secret-payload",
            }
        }
    }

    with pytest.raises(PreflightError, match="unexpected fields: credentials"):
        read_backend_settings(config)


def test_schema_rejects_invalid_backend_prefix(tmp_path: Path) -> None:
    config = synthetic_project_config()
    config["terraform"]["backend"]["prefix"] = "/invalid/"
    config_path = tmp_path / "invalid.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")

    with pytest.raises(PreflightError, match="failed JSON Schema"):
        validate_project_config(config_path, SCHEMA_PATH)


def test_schema_rejects_private_ssh_key(tmp_path: Path) -> None:
    config = synthetic_project_config()
    config["vms"]["infra"]["secret_mappings"]["POSTGRES_PASSWORD"] = (
        "-----BEGIN OPENSSH PRIVATE KEY-----"  # noqa: S105 - intentional invalid fixture
    )
    config_path = tmp_path / "private-key.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")

    with pytest.raises(PreflightError, match="failed JSON Schema"):
        validate_project_config(config_path, SCHEMA_PATH)


def test_command_uses_only_validated_backend_coordinates() -> None:
    command = build_init_command(
        Path("terraform-root"),
        "safe-state-bucket",
        "oilscope/dev",
        ["-migrate-state", "-input=false"],
    )

    assert command[-2:] == [
        "-backend-config=bucket=safe-state-bucket",
        "-backend-config=prefix=oilscope/dev",
    ]


@pytest.mark.parametrize(
    "argument",
    [
        "-backend=false",
        "-backend-config=credentials=secret.json",
        "-chdir=elsewhere",
    ],
)
def test_command_rejects_backend_or_directory_overrides(argument: str) -> None:
    with pytest.raises(PreflightError, match="forbidden arguments"):
        build_init_command(
            Path("terraform-root"),
            "safe-state-bucket",
            "oilscope/dev",
            [argument],
        )
