"""Run local role tests against mock secret APIs; never contact cloud services."""

import base64
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader

ROOT = Path(__file__).resolve().parents[3]
COLLECTION = ROOT / "infrastructure/ansible/oilscope/platform"


class MockSecrets(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, value):
        content = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        if self.path == "/token":
            self.reply({"access_token": "mock-only-token"})
        else:
            self.reply({"payload": {"data": base64.b64encode(b"test-value").decode()}})

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.reply({"SecretString": "test-value"})


class EdgeProxyConfigurationTests(unittest.TestCase):
    def test_edge_proxy_http_log_shipping_is_provider_scoped(self):
        role = COLLECTION / "roles/edge_proxy"
        tasks = yaml.safe_load((role / "tasks/main.yml").read_text())
        by_name = {task["name"]: task for task in tasks}

        gcp_when = by_name["Configure the Google Cloud Ops Agent for Traefik access logs"]["when"]
        aws_when = by_name["Configure the Amazon CloudWatch Agent for Traefik access logs"]["when"]
        self.assertIn('oilscope_cloud == "gcp"', gcp_when)
        self.assertIn('oilscope_cloud == "aws"', aws_when)

        compose = (COLLECTION / "roles/compose_project/templates/compose.proxy.yaml.j2").read_text()
        self.assertIn("--accesslog.format=json", compose)
        self.assertIn("--accesslog.filepath=/var/log/oilscope/traefik/access.log", compose)
        self.assertIn("--accesslog.fields.names.DownstreamStatus=keep", compose)
        self.assertIn('"/var/log/oilscope/traefik:/var/log/oilscope/traefik"', compose)

        gcp_config = (role / "templates/google-cloud-ops-agent.yaml.j2").read_text()
        aws_config = (role / "templates/amazon-cloudwatch-agent.json.j2").read_text()
        self.assertIn("type: parse_json", gcp_config)
        self.assertIn("edge_proxy_aws_log_group_name", aws_config)


class DatabaseModeConfigurationTests(unittest.TestCase):
    def test_managed_mode_uses_rabbitmq_and_skips_only_pgmq_migration(self):
        templates = COLLECTION / "roles/compose_project/templates"
        database = (templates / "compose.database.yaml.j2").read_text()
        fetcher = (templates / "compose.fetcher.yaml.j2").read_text()
        history = (templates / "compose.history.yaml.j2").read_text()
        migration = (ROOT / "infrastructure/docker/migrate.sh").read_text()

        self.assertIn("database_mode | default('self_hosted')", database)
        self.assertIn("rabbitmq:4-management", database)
        self.assertIn("rabbitmq-diagnostics", database)
        self.assertIn("redis:8.2.8-bookworm", database)
        self.assertIn("--requirepass", database)
        self.assertIn("redis-cli --no-auth-warning", database)
        self.assertIn("REDIS_BIND_ADDRESS", database)
        self.assertIn("MESSAGING_BACKEND", fetcher)
        self.assertIn("MESSAGING_BACKEND", history)
        self.assertIn("004_create_pgmq_queue.sql", migration)
        self.assertIn("DATABASE_MODE:-self_hosted", migration)

    def test_database_compose_renders_both_modes(self):
        templates = COLLECTION / "roles/compose_project/templates"
        # The template produces Compose YAML, not HTML; escaping changes its values.
        environment = Environment(
            loader=FileSystemLoader(templates),
            autoescape=False,  # noqa: S701
        )
        template = environment.get_template("compose.database.yaml.j2")
        registry = {"repository": "example.invalid/oilscope", "image_sha": "0" * 40}

        self_hosted = yaml.safe_load(
            template.render(
                compose_project_config={
                    "database_mode": "self_hosted",
                    "registry": registry,
                }
            )
        )
        managed = yaml.safe_load(
            template.render(
                compose_project_config={
                    "database_mode": "managed",
                    "registry": registry,
                }
            )
        )

        self.assertIn("postgres", self_hosted["services"])
        self.assertNotIn("rabbitmq", self_hosted["services"])
        self.assertIn("redis", self_hosted["services"])
        self.assertIn("rabbitmq", managed["services"])
        self.assertNotIn("postgres", managed["services"])
        self.assertIn("redis", managed["services"])
        self.assertEqual(managed["services"]["redis"]["restart"], "unless-stopped")
        self.assertIn("healthcheck", managed["services"]["redis"])
        self.assertIn("redis_data", managed["volumes"])

    def test_only_ui_receives_redis_application_configuration(self):
        templates = COLLECTION / "roles/compose_project/templates"
        ui = (templates / "compose.ui.yaml.j2").read_text()
        fetcher = (templates / "compose.fetcher.yaml.j2").read_text()
        history = (templates / "compose.history.yaml.j2").read_text()

        self.assertIn("REDIS_URL", ui)
        self.assertIn("REDIS_PASSWORD", ui)
        self.assertNotIn("DATABASE_URL", ui)
        self.assertNotIn("REDIS_", fetcher)
        self.assertNotIn("REDIS_", history)


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        collections = self.directory / "collections"
        link = collections / "ansible_collections/oilscope/platform"
        link.parent.mkdir(parents=True)
        link.symlink_to(COLLECTION, target_is_directory=True)
        self.env = os.environ.copy()
        self.env["ANSIBLE_COLLECTIONS_PATH"] = str(collections)
        self.env["PATH"] = str(Path(sys.executable).parent) + os.pathsep + self.env["PATH"]
        self.env["ANSIBLE_NOCOLOR"] = "1"
        self.inventory = self.directory / "inventory.yml"
        self.inventory.write_text(
            yaml.safe_dump(
                {
                    "all": {
                        "hosts": {
                            "localhost": {
                                "ansible_connection": "local",
                                "ansible_python_interpreter": sys.executable,
                                "oilscope_cloud": "gcp",
                                "oilscope_role": "fetcher",
                            }
                        }
                    }
                }
            )
        )

    def run_play(self, play, expect_success=True):
        path = self.directory / "play.yml"
        path.write_text(yaml.safe_dump(play))
        # The executable and arguments are fixed or repository-controlled test paths.
        result = subprocess.run(  # noqa: S603
            [
                str(Path(sys.executable).with_name("ansible-playbook")),
                "-i",
                str(self.inventory),
                str(path),
            ],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if expect_success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def test_secret_resolution_both_providers(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), MockSecrets)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        endpoint = f"http://127.0.0.1:{server.server_port}"
        self.env.update(
            {
                "AWS_ACCESS_KEY_ID": "mock-only",
                "AWS_SECRET_ACCESS_KEY": "mock-only",
                "AWS_EC2_METADATA_DISABLED": "true",
                "AWS_ENDPOINT_URL": endpoint,
            }
        )
        for provider in ["gcp", "aws"]:
            with self.subTest(provider=provider):
                self.run_play(
                    [
                        {
                            "name": "Resolve synthetic secrets using local mock APIs",
                            "hosts": "all",
                            "gather_facts": False,
                            "vars": {
                                "oilscope_cloud": provider,
                                "oilscope_region": "eu-central-1",
                                "resolve_secrets_config_path": str(
                                    ROOT / "project-config.example.json"
                                ),
                                "resolve_secrets_metadata_url": endpoint + "/token",
                                "resolve_secrets_secretmanager_url": endpoint,
                            },
                            "roles": ["oilscope.platform.resolve_secrets"],
                            "tasks": [
                                {
                                    "name": "Check the role to environment mapping",
                                    "ansible.builtin.assert": {
                                        "that": [
                                            (
                                                "resolve_secrets_result.POSTGRES_PASSWORD "
                                                "== 'test-value'"
                                            ),
                                            (
                                                "resolve_secrets_result.OILPRICEAPI_KEY "
                                                "== 'test-value'"
                                            ),
                                            "resolve_secrets_result.GHCR_TOKEN == 'test-value'",
                                        ]
                                    },
                                }
                            ],
                        }
                    ]
                )

    def test_topology_guard_rejects_mixed_clouds_before_ssh(self):
        inventory = yaml.safe_load(self.inventory.read_text())
        inventory["all"]["hosts"]["unreachable"] = {
            "oilscope_cloud": "aws",
            "ansible_host": "192.0.2.99",
        }
        self.inventory.write_text(yaml.safe_dump(inventory))
        result = self.run_play(
            [
                {
                    "name": "Reject unsupported topology",
                    "hosts": "localhost",
                    "gather_facts": False,
                    "roles": ["oilscope.platform.topology_guard"],
                }
            ],
            False,
        )
        self.assertIn("Deploy one application in one cloud", result.stdout)
        self.assertNotIn("Gather facts after topology validation", result.stdout)

    def test_topology_guard_accepts_single_cloud(self):
        self.run_play(
            [
                {
                    "name": "Accept local single-cloud fixture",
                    "hosts": "localhost",
                    "gather_facts": False,
                    "roles": ["oilscope.platform.topology_guard"],
                }
            ]
        )

    def test_all_deployment_playbooks_parse(self):
        binary = str(Path(sys.executable).with_name("ansible-playbook"))
        for play in sorted((COLLECTION / "playbooks").glob("*.yml")):
            # The executable and playbook come from trusted local test paths.
            result = subprocess.run(  # noqa: S603
                [binary, "--syntax-check", "-i", str(self.inventory), str(play)],
                env=self.env,
                text=True,
                capture_output=True,
                timeout=180,
            )
            self.assertEqual(result.returncode, 0, f"{play.name}: {result.stdout}{result.stderr}")


if __name__ == "__main__":
    unittest.main()
