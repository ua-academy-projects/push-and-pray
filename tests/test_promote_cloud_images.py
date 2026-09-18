from __future__ import annotations

import json
import os
import stat
import subprocess
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]
SCRIPT = REPOSITORY / "scripts" / "promote-cloud-images.sh"
CONFIG = REPOSITORY / "configs" / "project-config.aws-portable.json"
DIGEST = "sha256:" + "a" * 64


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def _environment(tmp_path: Path, target_digest: str) -> tuple[dict[str, str], Path]:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    calls = tmp_path / "docker-calls.log"
    _write_executable(
        bin_dir / "aws",
        """#!/usr/bin/env bash
set -eu
printf 'test-password\\n'
""",
    )
    _write_executable(
        bin_dir / "gcloud",
        """#!/usr/bin/env bash
set -eu
if [[ "$*" == "auth print-access-token" ]]; then
  printf 'test-gcp-token\n'
  exit 0
fi
exit 1
""",
    )
    _write_executable(
        bin_dir / "docker",
        """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "${FAKE_DOCKER_CALLS}"
case "$*" in
  "buildx version") exit 0 ;;
  "login "*) cat >/dev/null; exit 0 ;;
  "buildx imagetools inspect "*)
    image="$4"
    if [[ "$image" == target.invalid/* ]]; then
      digest="${FAKE_TARGET_DIGEST}"
    else
      digest="${FAKE_SOURCE_DIGEST}"
    fi
    printf '{"digest":"%s"}\\n' "$digest"
    ;;
  *) exit 0 ;;
esac
""",
    )
    environment = os.environ.copy()
    environment["PATH"] = f"{bin_dir}:{environment['PATH']}"
    environment["FAKE_DOCKER_CALLS"] = str(calls)
    environment["FAKE_SOURCE_DIGEST"] = DIGEST
    environment["FAKE_TARGET_DIGEST"] = target_digest
    environment["GHCR_TOKEN"] = "test-only-password"  # noqa: S105
    return environment, calls


def _registry_file(tmp_path: Path, provider: str = "aws") -> Path:
    registry = tmp_path / "registry.json"
    registry.write_text(
        json.dumps(
            {
                "provider": provider,
                "host": "target.invalid",
                "application": {
                    service: f"target.invalid/oilscope/{service}:sha"
                    for service in ("fetcher", "history", "ui", "database")
                },
                "managed": {},
            }
        ),
        encoding="utf-8",
    )
    return registry


def test_existing_matching_digest_is_idempotent(tmp_path: Path) -> None:
    environment, calls = _environment(tmp_path, DIGEST)

    result = subprocess.run(  # noqa: S603
        [str(SCRIPT), str(CONFIG), str(_registry_file(tmp_path))],
        cwd=REPOSITORY,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.count("Already promoted:") == 4
    invoked = calls.read_text(encoding="utf-8")
    assert "login --username darkkkCoDeR --password-stdin ghcr.io" in invoked
    assert "imagetools create" not in invoked


def test_existing_different_digest_is_rejected(tmp_path: Path) -> None:
    environment, calls = _environment(tmp_path, "sha256:" + "b" * 64)

    result = subprocess.run(  # noqa: S603
        [str(SCRIPT), str(CONFIG), str(_registry_file(tmp_path))],
        cwd=REPOSITORY,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode != 0
    assert "exists with a different digest" in result.stderr
    assert "imagetools create" not in calls.read_text(encoding="utf-8")


def test_gcp_uses_access_token_for_artifact_registry(tmp_path: Path) -> None:
    environment, calls = _environment(tmp_path, DIGEST)

    result = subprocess.run(  # noqa: S603
        [
            str(SCRIPT),
            str(CONFIG),
            str(_registry_file(tmp_path, provider="gcp")),
        ],
        cwd=REPOSITORY,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    invoked = calls.read_text(encoding="utf-8")
    assert "login --username oauth2accesstoken --password-stdin target.invalid" in invoked
    assert result.stdout.count("Already promoted:") == 4
