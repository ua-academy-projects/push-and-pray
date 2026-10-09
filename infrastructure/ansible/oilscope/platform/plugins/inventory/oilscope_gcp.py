# SPDX-License-Identifier: GPL-2.0-or-later
"""Discover OilScope instances in GCP, AWS and Azure from the project JSON."""

import json
import os
import tempfile

import yaml
from ansible.errors import AnsibleParserError
from ansible.plugins.inventory import BaseInventoryPlugin, Cacheable

DOCUMENTATION = r"""
name: oilscope_gcp
short_description: Discover OilScope VMs in GCP, AWS and Azure
version_added: "0.1.0"
description:
  - Reads the same project JSON as Terraform.
  - Uses C(default_cloud) and each VM's optional C(cloud) override.
  - Delegates discovery to the standard GCP, AWS and Azure inventory plugins.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description: Token identifying this inventory plugin.
    type: str
    required: true
    choices: [oilscope.platform.oilscope_gcp]
  project_config_path:
    description: Path to the project JSON shared with Terraform.
    type: str
    default: ../../terraform/config/dev.json
    env:
      - name: OILSCOPE_PROJECT_CONFIG
requirements:
  - google.cloud
  - amazon.aws
  - google-auth
  - boto3
  - azure.azcollection
"""

EXAMPLES = r"""
plugin: oilscope.platform.oilscope_gcp
cache: false
"""

DELEGATES = {
    "gcp": "google.cloud.gcp_compute",
    "aws": "amazon.aws.aws_ec2",
    "azure": "azure.azcollection.azure_rm",
}


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.platform.oilscope_gcp"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(("oilscope.yml", "oilscope.yaml"))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)
        config = self._load_config(path)

        selected_clouds = {
            vm.get("cloud", config["default_cloud"]) for vm in config["vms"].values()
        }
        builders = {
            "gcp": self._gcp_settings,
            "aws": self._aws_settings,
            "azure": self._azure_settings,
        }

        try:
            for cloud in sorted(selected_clouds):
                self._delegate(
                    inventory,
                    loader,
                    builders[cloud](config),
                    cloud,
                    cache,
                )
        except (KeyError, TypeError, ValueError) as error:
            message = f"invalid multi-cloud project configuration: {error}"
            raise AnsibleParserError(message) from error

    def _load_config(self, inventory_path):
        configured = os.path.expanduser(str(self.get_option("project_config_path")))
        config_path = (
            configured
            if os.path.isabs(configured)
            else os.path.join(os.path.dirname(os.path.abspath(inventory_path)), configured)
        )

        try:
            with open(os.path.normpath(config_path), encoding="utf-8") as handle:
                return json.load(handle)
        except (OSError, ValueError) as error:
            raise AnsibleParserError(f"could not read project configuration: {error}") from error

    @staticmethod
    def _location(config, cloud, kind):
        key = config["location"][kind]
        return config["clouds"][cloud][f"{kind}s"][key]

    @staticmethod
    def _bastion_port(config):
        return int(config["vms"]["bastion"]["ssh_port"])

    def _gcp_settings(self, config):
        cloud = "gcp"
        cloud_config = config["clouds"][cloud]
        bastion_port = self._bastion_port(config)
        ssh_user = sorted(config["ssh_users"])[0]
        is_bastion = "labels.role | default('') == 'bastion'"
        private_ip = "networkInterfaces[0].networkIP"
        public_ip = "networkInterfaces[0].accessConfigs[0].natIP"
        has_public_ip = "networkInterfaces[0].accessConfigs | default([])"
        metadata = (
            "metadata['items'] | default([]) | items2dict(key_name='key', value_name='value')"
        )

        return {
            "plugin": DELEGATES[cloud],
            "projects": [cloud_config["project_id"]],
            "zones": [self._location(config, cloud, "zone")],
            "filters": [
                f"labels.application = {config['name_prefix']}",
                f"labels.environment = {config['environment']}",
                "labels.cloud = gcp",
            ],
            "auth_kind": "application",
            "hostnames": ["name"],
            "vars_prefix": "gcp_",
            "keyed_groups": self._groups("labels"),
            "groups": {
                "workloads": "labels.role is defined and labels.role != 'bastion'",
                "k3s_servers": "labels.k3s_role | default('') == 'server'",
                "k3s_agents": "labels.k3s_role | default('') == 'agent'",
                "k3s_bootstrap": "labels.k3s_bootstrap | default('false') == 'true'",
            },
            "compose": {
                "internal_ip": private_ip,
                "public_ip": f"{public_ip} if {has_public_ip} else ''",
                "ansible_host": f"{public_ip} if {is_bastion} else {private_ip}",
                "ansible_user": f"'{ssh_user}'",
                "bastion_ssh_port": str(bastion_port),
                "oilscope_role": "labels.role | default('')",
                "oilscope_cloud": "labels.cloud | default('gcp')",
                "oilscope_region": f"'{self._location(config, cloud, 'region')}'",
                "k3s_role": "labels.k3s_role | default('')",
                "k3s_bootstrap": "labels.k3s_bootstrap | default('false') == 'true'",
                "database_mode": f"({metadata}).get('oilscope-database-mode', 'self_hosted')",
                "database_cloud": f"({metadata}).get('oilscope-database-cloud', 'gcp')",
                "database_host": f"({metadata}).get('oilscope-database-host', '')",
                "database_port": f"({metadata}).get('oilscope-database-port', '5432') | int",
                "database_name": f"({metadata}).get('oilscope-database-name', 'oil_tracker')",
                "database_user": f"({metadata}).get('oilscope-database-user', 'oil_tracker')",
                "database_sslmode": f"({metadata}).get('oilscope-database-sslmode', 'disable')",
                "database_secret_reference": f"({metadata}).get('oilscope-database-secret', '')",
                "queue_backend": f"({metadata}).get('oilscope-queue-backend', 'pgmq')",
                "queue_host": f"({metadata}).get('oilscope-queue-host', '')",
                "queue_port": f"({metadata}).get('oilscope-queue-port', '5672') | int",
                "queue_username": f"({metadata}).get('oilscope-queue-username', 'oilscope')",
                "queue_vhost": f"({metadata}).get('oilscope-queue-vhost', 'oilscope')",
                "queue_secret_reference": f"({metadata}).get('oilscope-queue-secret', '')",
            },
            "cache": bool(self.get_option("cache")),
        }

    def _aws_settings(self, config):
        cloud = "aws"
        bastion_port = self._bastion_port(config)
        is_bastion = "tags.role | default('') == 'bastion'"

        return {
            "plugin": DELEGATES[cloud],
            "regions": [self._location(config, cloud, "region")],
            "filters": {
                "instance-state-name": "running",
                "tag:application": config["name_prefix"],
                "tag:environment": config["environment"],
                "tag:cloud": cloud,
            },
            "hostnames": ["tag:Name"],
            "strict": False,
            "keyed_groups": self._groups("tags"),
            "groups": {
                "workloads": "tags.role is defined and tags.role != 'bastion'",
                "k3s_servers": "tags.k3s_role | default('') == 'server'",
                "k3s_agents": "tags.k3s_role | default('') == 'agent'",
                "k3s_bootstrap": "tags.k3s_bootstrap | default('false') == 'true'",
            },
            "compose": {
                "internal_ip": "private_ip_address",
                "public_ip": "public_ip_address | default('')",
                "ansible_host": f"public_ip_address if {is_bastion} else private_ip_address",
                "ansible_user": "'ubuntu'",
                "bastion_ssh_port": str(bastion_port),
                "oilscope_role": "tags.role | default('')",
                "oilscope_cloud": "tags.cloud | default('aws')",
                "oilscope_region": "placement.region | default(placement.availability_zone[:-1])",
                "k3s_role": "tags.k3s_role | default('')",
                "k3s_bootstrap": "tags.k3s_bootstrap | default('false') == 'true'",
                "database_mode": "tags.database_mode | default('self_hosted')",
                "database_cloud": "tags.database_cloud | default('aws')",
                "database_host": "tags.database_host | default('')",
                "database_port": "tags.database_port | default('5432') | int",
                "database_name": "tags.database_name | default('oil_tracker')",
                "database_user": "tags.database_user | default('oil_tracker')",
                "database_sslmode": "tags.database_sslmode | default('disable')",
                "database_secret_reference": "tags.database_secret | default('')",
                "queue_backend": "tags.queue_backend | default('pgmq')",
                "queue_host": "tags.queue_host | default('')",
                "queue_port": "tags.queue_port | default('5672') | int",
                "queue_username": "tags.queue_username | default('oilscope')",
                "queue_vhost": "tags.queue_vhost | default('oilscope')",
                "queue_secret_reference": "tags.queue_secret | default('')",
            },
            "cache": bool(self.get_option("cache")),
        }

    def _azure_settings(self, config):
        cloud = "azure"
        cloud_config = config["clouds"][cloud]
        bastion_port = self._bastion_port(config)
        resource_prefix = f"{config['name_prefix']}-{config['environment']}"
        primary_region = config["location"]["region"]
        region_keys = {
            vm.get("azure_region", primary_region)
            for vm in config["vms"].values()
            if vm.get("cloud", config["default_cloud"]) == cloud
        }
        if not region_keys:
            region_keys = {primary_region}
        resource_groups = sorted(
            f"{resource_prefix}-rg"
            if region_key == primary_region
            else f"{resource_prefix}-{region_key}-rg"
            for region_key in region_keys
        )
        ssh_user = sorted(config["ssh_users"])[0]
        public_ip = "(public_ipv4_address | default([]) | first) | default('')"
        private_ip = "(private_ipv4_addresses | default([]) | first) | default('')"
        is_bastion = "tags.role | default('') == 'bastion'"

        settings = {
            "plugin": DELEGATES[cloud],
            "auth_source": "auto",
            "include_vm_resource_groups": resource_groups,
            "plain_host_names": True,
            "hostnames": ["name"],
            "include_host_filters": [
                (
                    f"tags.application | default('') == '{config['name_prefix']}' "
                    f"and tags.environment | default('') == '{config['environment']}' "
                    "and tags.cloud | default('') == 'azure'"
                )
            ],
            "keyed_groups": self._groups("tags"),
            "conditional_groups": {
                "workloads": "tags.role is defined and tags.role != 'bastion'",
                "k3s_servers": "tags.k3s_role | default('') == 'server'",
                "k3s_agents": "tags.k3s_role | default('') == 'agent'",
                "k3s_bootstrap": "tags.k3s_bootstrap | default('false') == 'true'",
            },
            "hostvar_expressions": {
                "internal_ip": private_ip,
                "public_ip": public_ip,
                "ansible_host": f"{public_ip} if {is_bastion} else {private_ip}",
                "ansible_user": f"'{ssh_user}'",
                "bastion_ssh_port": str(bastion_port),
                "oilscope_role": "tags.role | default('')",
                "oilscope_cloud": "tags.cloud | default('azure')",
                "oilscope_region": "location",
                "k3s_role": "tags.k3s_role | default('')",
                "k3s_bootstrap": "tags.k3s_bootstrap | default('false') == 'true'",
                "azure_resource_group": "resource_group",
                "azure_vm_id": "id",
                "azure_identity_client_id": "tags.identity_client | default('')",
                "azure_identity_resource_id": "tags.identity_resource | default('')",
                "azure_secret_vault_uri": "tags.secret_vault_uri | default('')",
                "database_mode": "tags.database_mode | default('self_hosted')",
                "database_cloud": "tags.database_cloud | default('azure')",
                "database_host": "tags.database_host | default('')",
                "database_port": "tags.database_port | default('5432') | int",
                "database_name": "tags.database_name | default('oil_tracker')",
                "database_user": "tags.database_user | default('oil_tracker')",
                "database_sslmode": "tags.database_sslmode | default('disable')",
                "database_secret_reference": "tags.database_secret | default('')",
                "queue_backend": "tags.queue_backend | default('pgmq')",
                "queue_host": "tags.queue_host | default('')",
                "queue_port": "tags.queue_port | default('5672') | int",
                "queue_username": "tags.queue_username | default('oilscope')",
                "queue_vhost": "tags.queue_vhost | default('oilscope')",
                "queue_secret_reference": "tags.queue_secret | default('')",
            },
            "cache": bool(self.get_option("cache")),
        }
        subscription_id = cloud_config.get("subscription_id")
        if subscription_id:
            settings["subscription_id"] = subscription_id
        return settings

    @staticmethod
    def _groups(source):
        return [
            {"key": f"{source}.role", "prefix": "", "separator": ""},
            {"key": f"{source}.cloud", "prefix": "cloud", "separator": "_"},
        ]

    @staticmethod
    def _delegate(inventory, loader, settings, cloud, cache):
        from ansible.plugins.loader import inventory_loader

        suffixes = {
            "gcp": ".gcp.yml",
            "aws": ".aws_ec2.yml",
            "azure": ".azure_rm.yml",
        }
        suffix = suffixes[cloud]
        descriptor, generated = tempfile.mkstemp(prefix="oilscope-", suffix=suffix)
        os.close(descriptor)

        try:
            with open(generated, "w", encoding="utf-8") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)

            delegate = inventory_loader.get(DELEGATES[cloud])
            if delegate is None:
                raise AnsibleParserError(f"inventory plugin {DELEGATES[cloud]} is not installed")
            delegate.parse(inventory, loader, generated, cache=cache)
        finally:
            os.unlink(generated)
