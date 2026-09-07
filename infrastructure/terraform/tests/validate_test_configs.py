"""Validate representative project configurations against the JSON schema."""

import json
from copy import deepcopy
from pathlib import Path

from jsonschema import Draft202012Validator

TERRAFORM_ROOT = Path(__file__).resolve().parent.parent
REPOSITORY_ROOT = TERRAFORM_ROOT.parent.parent


def main() -> None:
    schema = json.loads((TERRAFORM_ROOT / "project-config.schema.json").read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)

    configurations = [
        REPOSITORY_ROOT / "project-config.example.json",
        TERRAFORM_ROOT / ".terraform" / "test-configs" / "aws-only.json",
        TERRAFORM_ROOT / ".terraform" / "test-configs" / "hybrid.json",
        TERRAFORM_ROOT / ".terraform" / "test-configs" / "region-override.json",
    ]

    for path in configurations:
        config = json.loads(path.read_text(encoding="utf-8"))
        validator.validate(config)
        print(f"valid: {path.relative_to(REPOSITORY_ROOT)}")

    base = json.loads(configurations[0].read_text(encoding="utf-8"))
    invalid = []
    for key in ["secret_mappings", "internal_ip", "public_endpoint"]:
        candidate = deepcopy(base)
        candidate["vms"]["history"][key] = {}
        invalid.append((f"obsolete VM field {key}", candidate))
    candidate = deepcopy(base)
    candidate["clouds"]["aws"]["account_id"] = "123456789012"
    invalid.append(("unused AWS account ID", candidate))
    candidate = deepcopy(base)
    candidate["registry"]["image_sha"] = "latest"
    invalid.append(("mutable deployment version", candidate))
    candidate = deepcopy(base)
    candidate["application"]["secret_mappings"]["history"]["invalid-env-name"] = "secret-id"
    invalid.append(("invalid application environment key", candidate))
    candidate = deepcopy(base)
    candidate["vms"]["history"]["assign_public_ip"] = True
    invalid.append(("public private-role VM", candidate))
    for name, candidate in invalid:
        if validator.is_valid(candidate):
            raise AssertionError(f"Schema accepted {name}")
        print(f"rejected: {name}")


if __name__ == "__main__":
    main()
