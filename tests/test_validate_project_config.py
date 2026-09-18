from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import pytest

REPOSITORY = Path(__file__).resolve().parents[1]
CONFIGS = REPOSITORY / "configs"
sys.path.insert(0, str(REPOSITORY))

from scripts.validate_project_config import ConfigError, validate_config  # noqa: E402


@pytest.mark.parametrize(
    "name",
    [
        "project-config.aws.json",
        "project-config.gcp.json",
        "project-config.aws-portable.json",
        "project-config.gcp-portable.json",
    ],
)
def test_supported_profile_matrix_is_valid(name: str) -> None:
    config = json.loads((CONFIGS / name).read_text(encoding="utf-8"))

    validate_config(config)


def test_aws_public_vm_must_use_public_subnet() -> None:
    config = json.loads(
        (CONFIGS / "project-config.aws-portable.json").read_text(encoding="utf-8")
    )
    config["vms"]["ui"]["internal_ip"] = "10.0.1.7"

    with pytest.raises(ConfigError, match="public_subnet_cidr"):
        validate_config(config)


def test_provider_reserved_address_is_rejected() -> None:
    config = json.loads(
        (CONFIGS / "project-config.aws-portable.json").read_text(encoding="utf-8")
    )
    config["vms"]["bastion"]["internal_ip"] = "10.0.0.3"

    with pytest.raises(ConfigError, match="reserved by aws"):
        validate_config(config)


def test_private_workload_cannot_receive_public_ip() -> None:
    config = json.loads(
        (CONFIGS / "project-config.gcp-portable.json").read_text(encoding="utf-8")
    )
    config["vms"]["history"]["assign_public_ip"] = True

    with pytest.raises(ConfigError, match="cannot have a public IP"):
        validate_config(config)


def test_overlapping_subnets_are_rejected() -> None:
    config = json.loads(
        (CONFIGS / "project-config.gcp-portable.json").read_text(encoding="utf-8")
    )
    config = copy.deepcopy(config)
    config["network"]["public_subnet_cidr"] = config["network"][
        "workload_subnet_cidr"
    ]

    with pytest.raises(ConfigError, match="network ranges overlap"):
        validate_config(config)


def test_managed_upstream_image_requires_digest() -> None:
    config = json.loads(
        (CONFIGS / "project-config.aws.json").read_text(encoding="utf-8")
    )
    config["managed_services"]["redis"]["source_image"] = "redis:7.4.6-alpine"

    with pytest.raises(ConfigError, match="exact sha256 digest"):
        validate_config(config)


def test_secret_value_is_rejected_without_echoing_it() -> None:
    config = json.loads(
        (CONFIGS / "project-config.aws-portable.json").read_text(encoding="utf-8")
    )
    leaked_value = "a" * 64
    config["secrets_by_role"]["fetcher"]["OILPRICEAPI_KEY"] = leaked_value

    with pytest.raises(ConfigError, match="looks like a secret value") as error:
        validate_config(config)

    assert leaked_value not in str(error.value)
