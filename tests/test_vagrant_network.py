import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class VagrantNetworkTests(unittest.TestCase):
    def setUp(self):
        self.entrypoint = (ROOT / "Vagrantfile").read_text(encoding="utf-8")
        self.vagrantfile = (
            ROOT / "infrastructure" / "vagrant" / "Vagrantfile"
        ).read_text(encoding="utf-8")

    def test_root_entrypoint_loads_infrastructure_configuration(self):
        self.assertIn(
            "infrastructure/vagrant/Vagrantfile",
            self.entrypoint,
        )

    def test_exactly_four_virtual_machines_exist(self):
        names = re.findall(r'^\s*name:\s*"([^"]+)"', self.vagrantfile, re.MULTILINE)
        self.assertEqual(
            names,
            ["database", "provider-service", "backend-service", "ui-service"],
        )
        self.assertNotIn("history-service", self.vagrantfile)

    def test_vmware_arm64_configuration_is_preserved(self):
        self.assertIn('config.vm.box_architecture = "arm64"', self.vagrantfile)
        self.assertIn('vmware_desktop', self.vagrantfile)


if __name__ == "__main__":
    unittest.main()
