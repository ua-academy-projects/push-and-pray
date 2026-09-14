"""Check migration selection and fail-fast behavior without a database server."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class MigrationRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.migrations = self.directory / "migrations"
        shutil.copytree(ROOT / "database/migrations", self.migrations)
        self.runner = self.directory / "migrate.sh"
        # Relocate only the image's fixed path; execute the real runner logic.
        self.runner.write_text(
            (ROOT / "infrastructure/docker/migrate.sh").read_text().replace(
                "/opt/petroscope/migrations", str(self.migrations)
            )
        )
        self.log = self.directory / "calls"
        for name, body in {
            "pg_isready": "exit 0\n",
            "psql": (
                'for arg do case "$arg" in --file=*) file=${arg#--file=};; esac; done\n'
                'printf "%s\\n" "$file" >> "$TEST_LOG"\n'
                '[ "${file##*/}" != "${FAIL_FILE:-}" ]\n'
            ),
        }.items():
            executable = self.directory / name
            executable.write_text("#!/bin/sh\n" + body)
            executable.chmod(0o755)

    def run_profile(self, profile=None, fail_file=""):
        env = dict(os.environ)
        env.pop("MIGRATION_PROFILE", None)
        env.update(
            PATH=f"{self.directory}:{env.get('PATH', '')}",
            PGHOST="unused", PGUSER="unused", PGDATABASE="unused",
            PGPASSWORD="unused", TEST_LOG=str(self.log), FAIL_FILE=fail_file,
        )
        if profile is not None:
            env["MIGRATION_PROFILE"] = profile
        result = subprocess.run(  # noqa: S603 -- fixed shell and test-owned script
            ["/bin/sh", str(self.runner)], env=env, capture_output=True,
            text=True, timeout=10, check=False,
        )
        calls = self.log.read_text().splitlines() if self.log.exists() else []
        return result, [Path(path).relative_to(self.migrations).as_posix() for path in calls]

    def test_default_runs_common_then_application(self):
        result, calls = self.run_profile()
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = [
            path.relative_to(self.migrations).as_posix()
            for group in ("common", "application")
            for path in sorted((self.migrations / group).glob("*.sql"))
        ]
        self.assertEqual(calls, expected)
        self.assertEqual(len(calls), 7)

    def test_cloud_runs_only_common_with_empty_profile(self):
        result, calls = self.run_profile("cloud")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 5)
        self.assertTrue(all(path.startswith("common/") for path in calls))

    def test_invalid_profile_fails_before_sql(self):
        result, calls = self.run_profile("invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MIGRATION_PROFILE", result.stderr)
        self.assertEqual(calls, [])

    def test_sql_failure_stops_later_migrations(self):
        result, calls = self.run_profile(fail_file="002_add_source_observed_at.sql")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 2)
        self.assertNotIn("migrations completed", result.stdout)

    def test_missing_common_sql_fails(self):
        for path in (self.migrations / "common").glob("*.sql"):
            path.unlink()
        result, calls = self.run_profile("cloud")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No common migrations", result.stderr)
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
