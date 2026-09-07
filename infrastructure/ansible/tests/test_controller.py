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
        self.inventory.write_text(yaml.safe_dump({"all": {"hosts": {"localhost": {
            "ansible_connection": "local", "ansible_python_interpreter": sys.executable,
            "oilscope_cloud": "gcp", "oilscope_role": "fetcher"}}}}))

    def run_play(self, play, expect_success=True):
        path = self.directory / "play.yml"
        path.write_text(yaml.safe_dump(play))
        result = subprocess.run([str(Path(sys.executable).with_name("ansible-playbook")),
                                 "-i", str(self.inventory), str(path)],
                                env=self.env, capture_output=True, text=True, timeout=180)
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
        self.env.update({"AWS_ACCESS_KEY_ID": "mock-only", "AWS_SECRET_ACCESS_KEY": "mock-only",
                         "AWS_EC2_METADATA_DISABLED": "true", "AWS_ENDPOINT_URL": endpoint})
        for provider in ["gcp", "aws"]:
            with self.subTest(provider=provider):
                self.run_play([{
                    "name": "Resolve synthetic secrets using local mock APIs",
                    "hosts": "all", "gather_facts": False,
                    "vars": {"oilscope_cloud": provider, "oilscope_region": "eu-central-1",
                             "resolve_secrets_config_path": str(ROOT / "project-config.example.json"),
                             "resolve_secrets_metadata_url": endpoint + "/token",
                             "resolve_secrets_secretmanager_url": endpoint},
                    "roles": ["oilscope.platform.resolve_secrets"],
                    "tasks": [{"name": "Check the role to environment mapping", "ansible.builtin.assert": {
                        "that": ["resolve_secrets_result.POSTGRES_PASSWORD == 'test-value'",
                                 "resolve_secrets_result.OILPRICEAPI_KEY == 'test-value'",
                                 "resolve_secrets_result.GHCR_TOKEN == 'test-value'"]}}],
                }])

    def test_topology_guard_rejects_mixed_clouds_before_ssh(self):
        inventory = yaml.safe_load(self.inventory.read_text())
        inventory["all"]["hosts"]["unreachable"] = {"oilscope_cloud": "aws", "ansible_host": "192.0.2.99"}
        self.inventory.write_text(yaml.safe_dump(inventory))
        result = self.run_play([{"name": "Reject unsupported topology", "hosts": "localhost",
                                 "gather_facts": False, "roles": ["oilscope.platform.topology_guard"]}], False)
        self.assertIn("Deploy one application in one cloud", result.stdout)
        self.assertNotIn("Gather facts after topology validation", result.stdout)

    def test_topology_guard_accepts_single_cloud(self):
        self.run_play([{"name": "Accept local single-cloud fixture", "hosts": "localhost",
                        "gather_facts": False, "roles": ["oilscope.platform.topology_guard"]}])

    def test_all_deployment_playbooks_parse(self):
        binary = str(Path(sys.executable).with_name("ansible-playbook"))
        for play in sorted((COLLECTION / "playbooks").glob("*.yml")):
            result = subprocess.run([binary, "--syntax-check", "-i", str(self.inventory), str(play)],
                                    env=self.env, text=True, capture_output=True, timeout=180)
            self.assertEqual(result.returncode, 0, f"{play.name}: {result.stdout}{result.stderr}")


if __name__ == "__main__":
    unittest.main()
