"""Credential-free tests for discovery composition and controller SSH options."""

import copy
import importlib.util
import json
import os
import shlex
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import jinja2
import yaml
from ansible.errors import AnsibleParserError
from ansible.inventory.data import InventoryData
from ansible.parsing.dataloader import DataLoader

ROOT = Path(__file__).resolve().parents[3]
PLUGIN = ROOT / "infrastructure/ansible/oilscope/platform/plugins/inventory/oilscope.py"
SPEC = importlib.util.spec_from_file_location("oilscope_inventory", PLUGIN)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.config = json.loads((ROOT / "project-config.example.json").read_text())
        self.plugin = MODULE.InventoryModule()
        options = {"bastion_role": "bastion", "workload_ssh_port": 22,
                   "project_config_path": "../../../project-config.example.json"}
        self.plugin.get_option = options.__getitem__
        self.env = jinja2.Environment(undefined=jinja2.StrictUndefined)

    def evaluate(self, settings, attributes):
        return {name: self.env.compile_expression(expr)(**attributes)
                for name, expr in settings["compose"].items()}

    def test_gcp_discovery_addresses_and_role_groups(self):
        settings = self.plugin._build_gcp_settings(self.config, "/tmp/project.json")
        self.assertEqual(settings["zones"], ["europe-west1-b"])
        self.assertIn("labels.cloud = gcp", settings["filters"])
        self.assertEqual(settings["keyed_groups"][0]["key"], "labels.role")
        attributes = {"labels": {"role": "bastion"}, "networkInterfaces": [
            {"networkIP": "10.0.0.2", "accessConfigs": [{"natIP": "192.0.2.1"}]}]}
        result = self.evaluate(settings, attributes)
        self.assertEqual((result["ansible_host"], result["ansible_port"]), ("192.0.2.1", 8787))
        self.assertEqual(result["project_config_path"], "/tmp/project.json")
        attributes["labels"]["role"] = "database"
        attributes["networkInterfaces"][0]["accessConfigs"] = []
        result = self.evaluate(settings, attributes)
        self.assertEqual((result["ansible_host"], result["ansible_port"]), ("10.0.0.2", 22))
        self.assertEqual(result["oilscope_role"], "database")
        self.assertTrue(self.env.compile_expression(settings["groups"]["workloads"])(**attributes))

    def test_aws_discovery_addresses_and_role_groups(self):
        self.config["default_cloud"] = "aws"
        settings = self.plugin._build_aws_settings(self.config, "/tmp/aws.json")
        self.assertEqual(settings["regions"], ["eu-central-1"])
        self.assertEqual(settings["filters"]["tag:cloud"], "aws")
        self.assertEqual(settings["keyed_groups"][0]["key"], "tags.role")
        attributes = {"tags": {"role": "bastion"}, "private_ip_address": "10.0.0.2",
                      "public_ip_address": "192.0.2.2"}
        result = self.evaluate(settings, attributes)
        self.assertEqual((result["ansible_host"], result["ansible_port"]), ("192.0.2.2", 8787))
        attributes["tags"]["role"] = "ui"
        result = self.evaluate(settings, attributes)
        self.assertEqual((result["ansible_host"], result["ansible_port"]), ("10.0.0.2", 22))

    def test_parse_delegates_only_to_used_providers_and_cleans_files(self):
        for hybrid in [False, True]:
            config = copy.deepcopy(self.config)
            if hybrid:
                config["vms"]["ui"]["cloud"] = "aws"
            calls = []
            files = []

            def delegate(name, inventory, loader, generated, cache):
                settings = yaml.safe_load(Path(generated).read_text())
                calls.append(settings["plugin"])
                files.append(Path(generated))

            with tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "project.json"
                path.write_text(json.dumps(config))
                with patch.dict(os.environ, {"OILSCOPE_PROJECT_CONFIG": str(path)}), \
                        patch.object(self.plugin, "_read_config_data"), \
                        patch.object(self.plugin, "_delegate", side_effect=delegate):
                    self.plugin.parse(InventoryData(), DataLoader(), str(ROOT / "infrastructure/ansible/inventory/oilscope.yml"))
            self.assertEqual(calls, [MODULE.GCP_DELEGATE, MODULE.AWS_DELEGATE] if hybrid else [MODULE.GCP_DELEGATE])
            self.assertTrue(all(not path.exists() for path in files))

    def test_region_override(self):
        self.config["cloud_mappings"]["regions"]["alternate"] = {
            "gcp": {"region": "us-central1", "zone": "us-central1-a"}}
        for vm in self.config["vms"].values():
            vm["region"] = "alternate"
        self.assertEqual(self.plugin._provider_zones(self.config, "gcp"), ["us-central1-a"])

    def test_invalid_region_mapping(self):
        self.config["vms"]["history"]["region"] = "missing"
        with self.assertRaises(AnsibleParserError):
            self.plugin._build_gcp_settings(self.config, "/tmp/project.json")

    def test_nested_proxy_has_explicit_key_and_final_port(self):
        variables = yaml.safe_load((ROOT / "infrastructure/ansible/inventory/group_vars/workloads.yml").read_text())
        self.env.filters["quote"] = shlex.quote
        result = self.env.from_string(variables["ansible_ssh_common_args"]).render(
            oilscope_ssh_base_args="-o StrictHostKeyChecking=accept-new",
            oilscope_bastion_ssh_port=8787,
            oilscope_bastion_private_key_file="/home/operator/keys/my key",
            oilscope_bastion_address="192.0.2.1", ansible_user="operator")
        args = shlex.split(result)
        proxy = next(arg.split("=", 1)[1] for arg in args if arg.startswith("ProxyCommand="))
        nested = shlex.split(proxy)
        self.assertEqual(nested[nested.index("-p") + 1], "8787")
        self.assertEqual(nested[nested.index("-i") + 1], "/home/operator/keys/my key")
        self.assertIn("IdentitiesOnly=yes", nested)
        self.assertIn("operator@192.0.2.1", nested)


if __name__ == "__main__":
    unittest.main()
