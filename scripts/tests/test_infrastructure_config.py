"""Offline checks only: no Terraform, credentials or cloud API calls."""

import ast
import copy
import ipaddress
import json
import re
import unittest
from pathlib import Path

from jsonschema import FormatChecker, validators

ROOT = Path(__file__).resolve().parents[2]
TF = ROOT / "infrastructure/terraform"
LOCATIONS = (
    "default",
    "europe-west",
    "europe-central",
    "america-east",
    "america-west",
    "asia-southeast",
)


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


class ConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        schema = read_json(TF / "project-config.schema.json")
        validator = validators.validator_for(schema)
        validator.check_schema(schema)
        cls.validator = validator(schema, format_checker=FormatChecker())
        cls.example = read_json(ROOT / "project-config.example.json")

    def assert_config(self, config):
        self.validator.validate(config)

    def test_example_and_optional_local_configuration(self):
        self.assert_config(self.example)
        local = TF / "config/dev.json"
        if local.exists():
            self.assert_config(read_json(local))

    def test_locations_and_dictionaries_for_each_cloud(self):
        paths = [ROOT / "project-config.example.json"]
        if (TF / "config/dev.json").exists():
            paths.append(TF / "config/dev.json")
        for path in paths:
            for cloud in ("aws", "gcp"):
                for location in LOCATIONS:
                    with self.subTest(file=path.name, cloud=cloud, location=location):
                        config = copy.deepcopy(read_json(path))
                        config["default_cloud"] = cloud
                        config["location"] = dict(region=location, zone=location)
                        for vm in config["vms"].values():
                            vm.pop("cloud", None)
                        self.assert_config(config)
                        provider = config["clouds"][cloud]
                        region = provider["regions"][location]
                        zone = provider["zones"][location]
                        self.assertTrue(zone.startswith(region))
                        for vm in config["vms"].values():
                            self.assertTrue(provider["machine_types"][vm["machine_type"]])
                            self.assertTrue(provider["disk_types"][vm["boot_disk"]["type"]])
                            self.assertTrue(provider["images"][location][vm["image"]])

    def test_cloud_specific_subnets_and_addresses(self):
        for cloud in ("aws", "gcp"):
            network = dict(self.example["network"])
            network.update(self.example["clouds"][cloud].get("network", {}))
            nets = [
                ipaddress.ip_network(network[f"{name}_subnet_cidr"])
                for name in ("management", "workload")
            ]
            self.assertFalse(nets[0].overlaps(nets[1]))
            seen = set()
            for vm in self.example["vms"].values():
                public_roles = {"bastion", "ui"} if cloud == "aws" else {"bastion"}
                subnet = nets[0 if vm["role"] in public_roles else 1]
                address = ipaddress.ip_address(
                    vm.get("internal_ips", {}).get(cloud, vm["internal_ip"])
                )
                self.assertIn(address, subnet)
                self.assertNotIn(address, seen)
                seen.add(address)
                if cloud == "aws":
                    self.assertLessEqual(subnet.prefixlen, 28)
                    self.assertGreaterEqual(int(address) - int(subnet.network_address), 4)
                self.assertNotEqual(address, subnet.broadcast_address)

    def test_optional_disks_and_rejection_of_incomplete_disk(self):
        config = copy.deepcopy(self.example)
        vm = next(iter(config["vms"].values()))
        disk = {
            "device_names": {"aws": "/dev/sdf", "gcp": "data"},
            "size_gb": 20,
            "type": "balanced",
        }
        vm["additional_disks"] = {"data": disk}
        self.assert_config(config)
        del disk["device_names"]
        self.assertFalse(self.validator.is_valid(config))


class ModuleStructureTests(unittest.TestCase):
    def test_root_only_loads_configuration(self):
        text = (TF / "locals.tf").read_text()
        self.assertEqual(
            len(re.findall(r"config\s*=\s*jsondecode\(file\(var.project_config_path\)\)", text)),
            1,
        )

    def test_flat_modules_and_declared_inputs(self):
        main = (TF / "main.tf").read_text()
        modules = dict(re.findall(r'module\s+"(\w+)"\s*\{\s*source\s*=\s*"([^"]+)"', main))
        self.assertEqual(len(modules), 12)
        for name, source in modules.items():
            directory = TF / source
            self.assertTrue(directory.is_dir(), name)
            text = "\n".join(p.read_text() for p in directory.glob("*.tf"))
            self.assertNotRegex(text, r'(?m)^module\s+"')
            declared = set(re.findall(r'variable\s+"(\w+)"', text))
            referenced = set(re.findall(r"\bvar\.(\w+)", text))
            self.assertFalse(referenced - declared, (name, referenced - declared))
        outputs = (TF / "outputs.tf").read_text()
        for module, output in re.findall(r"\bmodule\.(\w+)\.(\w+)", main + outputs):
            text = "\n".join(p.read_text() for p in (TF / modules[module]).glob("*.tf"))
            self.assertRegex(text, rf'output\s+"{output}"')

    def test_templates_retained_but_not_attached(self):
        template_dir = TF / "modules/gcp-vm/templates"
        for name in ("run.sh", "cloud-config.yaml.tftpl", "bastion-startup.sh.tftpl"):
            self.assertTrue((template_dir / name).exists())
        for module in ("aws-vm", "gcp-vm"):
            text = "\n".join(p.read_text() for p in (TF / "modules" / module).glob("*.tf"))
            self.assertNotIn("templatefile(", text)
            self.assertNotRegex(text, r"\buser_data\s*=")
            self.assertNotIn('"startup-script"', text)


class InventorySettingsTests(unittest.TestCase):
    def test_existing_inventory_reads_every_location(self):
        # Compile only pure settings methods: no Ansible imports or discovery.
        path = ROOT / "infrastructure/ansible/oilscope/platform/plugins/inventory/oilscope_gcp.py"
        tree = ast.parse(path.read_text())
        cls = next(node for node in tree.body if isinstance(node, ast.ClassDef))
        cls.bases = []
        keep = {"_location", "_bastion_port", "_gcp_settings", "_aws_settings", "_groups"}
        cls.body = [
            node for node in cls.body if isinstance(node, ast.FunctionDef) and node.name in keep
        ]
        module = ast.fix_missing_locations(ast.Module(body=[cls], type_ignores=[]))
        namespace = {"DELEGATES": {"aws": "amazon.aws.aws_ec2", "gcp": "google.cloud.gcp_compute"}}
        exec(compile(module, str(path), "exec"), namespace)  # noqa: S102
        plugin = namespace["InventoryModule"]()
        plugin.get_option = lambda name: False
        config = read_json(ROOT / "project-config.example.json")
        for location in LOCATIONS:
            config["location"] = dict(region=location, zone=location)
            self.assertEqual(
                plugin._aws_settings(config)["regions"],
                [config["clouds"]["aws"]["regions"][location]],
            )
            self.assertEqual(
                plugin._gcp_settings(config)["zones"], [config["clouds"]["gcp"]["zones"][location]]
            )


if __name__ == "__main__":
    unittest.main()
