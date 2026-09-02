"""Validate representative project configurations against the JSON schema."""

import json
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
    ]

    for path in configurations:
        config = json.loads(path.read_text(encoding="utf-8"))
        validator.validate(config)
        print(f"valid: {path.relative_to(REPOSITORY_ROOT)}")


if __name__ == "__main__":
    main()
