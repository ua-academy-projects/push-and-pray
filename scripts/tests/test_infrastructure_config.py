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
            for cloud in ("aws", "gcp", "azure"):
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
                        if cloud == "azure":
                            self.assertRegex(zone, r"^[1-3]$")
                        else:
                            self.assertTrue(zone.startswith(region))
                        for vm in config["vms"].values():
                            self.assertTrue(provider["machine_types"][vm["machine_type"]])
                            self.assertTrue(provider["disk_types"][vm["boot_disk"]["type"]])
                            self.assertTrue(provider["images"][location][vm["image"]])

    def test_cloud_specific_subnets_and_addresses(self):
        for cloud in ("aws", "gcp", "azure"):
            network = dict(self.example["network"])
            network.update(self.example["clouds"][cloud].get("network", {}))
            nets = [
                ipaddress.ip_network(network[f"{name}_subnet_cidr"])
                for name in ("management", "workload")
            ]
            self.assertFalse(nets[0].overlaps(nets[1]))
            seen = set()
            for vm in self.example["vms"].values():
                public_roles = {"bastion", "ui"} if cloud in {"aws", "azure"} else {"bastion"}
                subnet = nets[0 if vm["role"] in public_roles else 1]
                address = ipaddress.ip_address(
                    vm.get("internal_ips", {}).get(cloud, vm["internal_ip"])
                )
                self.assertIn(address, subnet)
                self.assertNotIn(address, seen)
                seen.add(address)
                if cloud in {"aws", "azure"}:
                    self.assertLessEqual(subnet.prefixlen, 28)
                    self.assertGreaterEqual(int(address) - int(subnet.network_address), 4)
                self.assertNotEqual(address, subnet.broadcast_address)

    def test_cloud_networks_do_not_overlap(self):
        paths = [ROOT / "project-config.example.json"]
        local = TF / "config/dev.json"
        if local.exists():
            paths.append(local)

        for path in paths:
            config = read_json(path)
            networks = []
            for cloud in ("aws", "gcp"):
                network = dict(config["network"])
                network.update(config["clouds"][cloud]["network"])
                networks.append((cloud, ipaddress.ip_network(network["vpc_cidr"])))

            azure = config["clouds"]["azure"]
            networks.append(
                ("azure-default", ipaddress.ip_network(azure["network"]["vnet_cidr"]))
            )
            for region, network in azure.get("regional_networks", {}).items():
                networks.append(
                    (f"azure-{region}", ipaddress.ip_network(network["vnet_cidr"]))
                )

            for index, (left_name, left_network) in enumerate(networks):
                for right_name, right_network in networks[index + 1 :]:
                    with self.subTest(
                        file=path.name, left=left_name, right=right_name
                    ):
                        self.assertFalse(left_network.overlaps(right_network))

    def test_k3s_topology(self):
        nodes = {
            name: vm
            for name, vm in self.example["vms"].items()
            if vm["role"] == "k3s"
        }
        servers = {
            name: vm for name, vm in nodes.items() if vm["k3s_role"] == "server"
        }
        agents = {
            name: vm for name, vm in nodes.items() if vm["k3s_role"] == "agent"
        }
        bootstrap = [
            name for name, vm in servers.items() if vm.get("k3s_bootstrap", False)
        ]

        self.assertEqual(len(servers), 3)
        self.assertEqual(len(agents), 1)
        self.assertEqual(len(bootstrap), 1)
        self.assertTrue(agents["k3s-agent-1"]["assign_public_ip"])
        self.assertIn("public_endpoint", agents["k3s-agent-1"])

    def test_tailscale_has_one_bastion_and_a_router_per_active_cloud(self):
        paths = [ROOT / "project-config.example.json"]
        local = TF / "config/dev.json"
        if local.exists():
            paths.append(local)

        for path in paths:
            config = read_json(path)
            if not config.get("tailscale", {}).get("enabled", False):
                continue
            vms = config["vms"]
            bastions = [vm for vm in vms.values() if vm["role"] == "bastion"]
            self.assertEqual(len(bastions), 1, path)
            active_clouds = {
                vm.get("cloud", config["default_cloud"])
                for vm in vms.values()
                if vm["role"] != "bastion"
            }
            for cloud in active_clouds:
                with self.subTest(file=path.name, cloud=cloud):
                    self.assertTrue(
                        any(
                            vm.get("cloud", config["default_cloud"]) == cloud
                            and vm["role"] == "k3s"
                            and vm.get("k3s_role") == "server"
                            for vm in vms.values()
                        )
                    )

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

    def test_grouped_modules_and_declared_inputs(self):
        main = (TF / "main.tf").read_text()
        modules = dict(
            re.findall(r'module\s+"([\w-]+)"\s*\{\s*source\s*=\s*"([^"]+)"', main)
        )
        expected_modules = {
            "gcp_apis",
            "iam",
            "aws_network",
            "aws_security",
            "aws_rds",
            "aws_secrets",
            "aws_vm",
            "gcp_network",
            "gcp_security",
            "gcp_cloud_sql",
            "gcp_vm",
            "gcp_secrets",
            "azure_network",
            "azure_security",
            "azure_identity",
            "azure_postgresql",
            "azure_vm",
            "azure-monitoring",
            "aws-monitoring",
            "gcp-monitoring",
        }
        self.assertEqual(set(modules), expected_modules)
        for name, source in modules.items():
            directory = TF / source
            self.assertTrue(directory.is_dir(), name)
            text = "\n".join(p.read_text() for p in directory.glob("*.tf"))
            self.assertNotRegex(text, r'(?m)^module\s+"')
            declared = set(re.findall(r'variable\s+"(\w+)"', text))
            referenced = set(re.findall(r"\bvar\.(\w+)", text))
            self.assertFalse(referenced - declared, (name, referenced - declared))
        outputs = (TF / "outputs.tf").read_text()
        for module, output in re.findall(r"\bmodule\.([\w-]+)\.(\w+)", main + outputs):
            text = "\n".join(p.read_text() for p in (TF / modules[module]).glob("*.tf"))
            self.assertRegex(text, rf'output\s+"{output}"')

    def test_legacy_templates_retained_and_tailscale_cloud_init_attached(self):
        template_dir = TF / "modules/gcp/gcp-vm/templates"
        for name in ("run.sh", "cloud-config.yaml.tftpl", "bastion-startup.sh.tftpl"):
            self.assertTrue((template_dir / name).exists())

        module_text = {
            cloud: "\n".join(
                path.read_text()
                for path in (TF / "modules" / cloud / f"{cloud}-vm").glob("*.tf")
            )
            for cloud in ("aws", "gcp", "azure")
        }
        for cloud in ("aws", "gcp"):
            self.assertNotIn("templatefile(", module_text[cloud])
            self.assertNotIn('"startup-script"', module_text[cloud])

        self.assertRegex(module_text["aws"], r"\buser_data\s*=.*tailscale_cloud_init")
        self.assertIn('"user-data"', module_text["gcp"])
        self.assertRegex(module_text["azure"], r"\bcustom_data\s*=.*tailscale_cloud_init")

        root_tailscale = (TF / "tailscale.tf").read_text()
        self.assertIn('source = "./modules/tailscale"', root_tailscale)

        tailscale_module = "\n".join(
            path.read_text() for path in (TF / "modules/tailscale").glob("*.tf")
        )
        self.assertIn('source  = "tailscale/tailscale/cloudinit"', tailscale_module)
        self.assertIn(
            'resource "tailscale_tailnet_key" "bootstrap"', tailscale_module
        )


class InventorySettingsTests(unittest.TestCase):
    def test_existing_inventory_reads_every_location(self):
        # Compile only pure settings methods: no Ansible imports or discovery.
        path = ROOT / "infrastructure/ansible/oilscope/platform/plugins/inventory/oilscope_gcp.py"
        tree = ast.parse(path.read_text())
        cls = next(node for node in tree.body if isinstance(node, ast.ClassDef))
        cls.bases = []
        keep = {
            "_location",
            "_bastion_port",
            "_gcp_settings",
            "_aws_settings",
            "_azure_settings",
            "_groups",
        }
        cls.body = [
            node for node in cls.body if isinstance(node, ast.FunctionDef) and node.name in keep
        ]
        module = ast.fix_missing_locations(ast.Module(body=[cls], type_ignores=[]))
        namespace = {
            "DELEGATES": {
                "aws": "amazon.aws.aws_ec2",
                "gcp": "google.cloud.gcp_compute",
                "azure": "azure.azcollection.azure_rm",
            }
        }
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
            self.assertEqual(
                plugin._gcp_settings(config)["compose"]["ansible_user"],
                f"'{sorted(config['ssh_users'])[0]}'",
            )
            azure = plugin._azure_settings(config)
            self.assertEqual(
                azure["include_vm_resource_groups"],
                [f"{config['name_prefix']}-{config['environment']}-rg"],
            )
            self.assertEqual(
                azure["hostvar_expressions"]["oilscope_region"], "location"
            )
            for settings, group_key in (
                (plugin._aws_settings(config), "groups"),
                (plugin._gcp_settings(config), "groups"),
                (azure, "conditional_groups"),
            ):
                groups = settings[group_key]
                self.assertIn("k3s_servers", groups)
                self.assertIn("k3s_agents", groups)
                self.assertIn("k3s_bootstrap", groups)

    def test_workload_proxy_uses_the_bastion_user(self):
        path = ROOT / "infrastructure/ansible/inventory/group_vars/workloads.yml"
        text = path.read_text(encoding="utf-8")
        self.assertIn("hostvars[oilscope_bastion_host].ansible_user", text)
        self.assertIn("oilscope_bastion_user }}@{{ oilscope_bastion_address", text)


if __name__ == "__main__":
    unittest.main()
