import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class VagrantNetworkTests(unittest.TestCase):
    def setUp(self):
        self.vagrantfile = (ROOT / "Vagrantfile").read_text(encoding="utf-8")

    def test_exactly_four_virtual_machines_exist(self):
        names = re.findall(r'^\s*name:\s*"([^"]+)"', self.vagrantfile, re.MULTILINE)
        self.assertEqual(
            names,
            ["database", "provider-service", "backend-service", "ui-service"],
        )
        self.assertNotIn("history-service", self.vagrantfile)

    def test_private_ips_are_correct(self):
        for ip in (
            "192.168.56.10",
            "192.168.56.11",
            "192.168.56.12",
            "192.168.56.13",
        ):
            self.assertEqual(self.vagrantfile.count(ip), 1)

    def test_forwarded_ports_are_correct(self):
        pattern = re.compile(
            r'guest:\s*5000,\s*host:\s*8080,',
            re.MULTILINE,
        )
        self.assertRegex(self.vagrantfile, pattern)

    def test_only_ui_forward_is_public(self):
        self.assertEqual(self.vagrantfile.count('host_ip: "0.0.0.0"'), 1)

    def test_vmware_arm64_configuration_is_preserved(self):
        self.assertIn('config.vm.box_architecture = "arm64"', self.vagrantfile)
        self.assertIn('vmware_desktop', self.vagrantfile)


if __name__ == "__main__":
    unittest.main()
