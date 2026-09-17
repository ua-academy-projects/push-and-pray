# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Discover OilScope virtual machines in GCP and AWS."""

import json
import os
import shlex
import tempfile

import yaml
from ansible.errors import AnsibleParserError
from ansible.plugins.inventory import BaseInventoryPlugin
from ansible.utils.display import Display

DOCUMENTATION = r"""
name: oilscope_cloud
short_description: Discover OilScope virtual machines in GCP and AWS
version_added: "0.1.0"
author:
  - Push and Pray team
description:
  - Discovers the VMs in the Terraform project configuration through GCP and AWS.
options:
  plugin:
    description: Token that identifies this plugin.
    type: str
    required: true
    choices:
      - oilscope.platform.oilscope_cloud
  project_config_path:
    description:
      - Path to the project configuration JSON.
      - Can also be set with C(OILSCOPE_PROJECT_CONFIG).
    type: str
    default: project-config.json
    env:
      - name: OILSCOPE_PROJECT_CONFIG
  ssh_user:
    description:
      - SSH user used for every discovered host.
      - Defaults to C(ubuntu) on AWS and the first configured SSH user on GCP.
    type: str
    default: ""
    env:
      - name: OILSCOPE_SSH_USER
  ssh_private_key_file:
    description:
      - Optional SSH private key path.
      - OpenSSH default identities and SSH agent configuration are used when omitted.
    type: str
    default: ""
    env:
      - name: OILSCOPE_SSH_KEY
"""

EXAMPLES = r"""
# inventory/oilscope.yml
plugin: oilscope.platform.oilscope_cloud
"""

DELEGATES = {
    "aws": "amazon.aws.aws_ec2",
    "gcp": "google.cloud.gcp_compute",
}

display = Display()


class InventoryModule(BaseInventoryPlugin):
    NAME = "oilscope.platform.oilscope_cloud"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(("oilscope.yml", "oilscope.yaml"))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        config = self._load_project_config(path)
        inventory.set_variable("all", "project_config_path", self.project_config_path)
        virtual_machines = self._virtual_machines(config)

        for cloud in DELEGATES:
            inventory.add_group(cloud)

        for cloud in DELEGATES:
            cloud_vms = {name: vm for name, vm in virtual_machines.items() if vm["cloud"] == cloud}
            if not cloud_vms:
                continue

            settings = self._build_settings(cloud, config, cloud_vms)
            discovered = self._discover(cloud, loader, settings)
            self._add_hosts(inventory, cloud, config, cloud_vms, discovered)

    def _resolve_config_path(self, inventory_path):
        configured = str(self.get_option("project_config_path"))

        if os.path.isabs(configured):
            return os.path.normpath(configured)

        from_cwd = os.path.abspath(configured)
        if os.path.isfile(from_cwd):
            return from_cwd

        beside_inventory = os.path.join(
            os.path.dirname(os.path.abspath(inventory_path)), configured
        )
        return os.path.normpath(beside_inventory)

    def _load_project_config(self, inventory_path):
        config_path = self._resolve_config_path(inventory_path)
        self.project_config_path = config_path

        try:
            with open(config_path, "rb") as handle:
                config = json.load(handle)
        except (OSError, ValueError) as error:
            raise AnsibleParserError(
                f"could not load the project configuration at {config_path}: {error}"
            ) from error

        if not isinstance(config, dict):
            raise AnsibleParserError(
                f"the project configuration at {config_path} must contain a JSON object"
            )

        return config

    @staticmethod
    def _required_string(mapping, key, context="project configuration"):
        value = mapping.get(key)
        if not isinstance(value, str) or not value:
            raise AnsibleParserError(f"{context} must define a non-empty string {key!r}")
        return value

    def _virtual_machines(self, config):
        default_cloud = self._required_string(config, "default_cloud")
        default_location = self._required_string(config, "default_location")
        name_prefix = self._required_string(config, "name_prefix")
        environment = self._required_string(config, "environment")
        locations = config.get("locations")
        vms = config.get("vms")
        bastion = config.get("bastion")

        if not isinstance(locations, dict):
            raise AnsibleParserError("the project configuration must define a 'locations' object")
        if not isinstance(vms, dict):
            raise AnsibleParserError("the project configuration must define a 'vms' object")
        if not isinstance(bastion, dict):
            raise AnsibleParserError("the project configuration must define a 'bastion' object")
        virtual_machines = {
            **vms,
            "bastion": {
                **bastion,
                "tags": ["bastion"],
            },
        }

        normalized = {}
        for name, vm in virtual_machines.items():
            if not isinstance(vm, dict):
                raise AnsibleParserError(f"VM {name!r} must be an object")

            cloud = vm.get("cloud", default_cloud)
            location = vm.get("location", default_location)
            location_settings = locations.get(location)

            if cloud not in DELEGATES:
                raise AnsibleParserError(f"VM {name!r} uses unsupported cloud {cloud!r}")
            if not isinstance(location_settings, dict) or not isinstance(
                location_settings.get(cloud), dict
            ):
                raise AnsibleParserError(
                    f"location {location!r} does not define settings for {cloud!r}"
                )

            tags = vm.get("tags")
            if (
                not isinstance(tags, list)
                or not tags
                or not all(isinstance(tag, str) and tag for tag in tags)
            ):
                raise AnsibleParserError(f"VM {name!r} must define a non-empty 'tags' array")

            normalized[name] = {
                **vm,
                "cloud": cloud,
                "location": location,
                "provider_location": location_settings[cloud],
                "resource_name": f"{name_prefix}-{environment}-{name}",
            }

        return normalized

    def _build_settings(self, cloud, config, virtual_machines):
        if cloud == "gcp":
            cloud_settings = config.get("cloud_settings", {}).get("gcp", {})
            project_id = self._required_string(cloud_settings, "project_id", "GCP settings")
            zones = sorted({vm["provider_location"]["zone"] for vm in virtual_machines.values()})

            return {
                "plugin": DELEGATES[cloud],
                "projects": [project_id],
                "zones": zones,
                "filters": ["status = RUNNING"],
                "auth_kind": "application",
                "hostnames": ["name"],
                "compose": {
                    "oilscope_discovered_public_ip": (
                        "networkInterfaces[0].accessConfigs[0].natIP "
                        "if networkInterfaces[0].accessConfigs | default([]) else ''"
                    )
                },
            }

        regions = sorted({vm["provider_location"]["region"] for vm in virtual_machines.values()})
        names = sorted(vm["resource_name"] for vm in virtual_machines.values())
        settings = {
            "plugin": DELEGATES[cloud],
            "regions": regions,
            "filters": {
                "instance-state-name": "running",
                "tag:Name": names,
            },
            "hostnames": ["tag:Name"],
            "strict": False,
            "compose": {"oilscope_discovered_public_ip": "public_ip_address | default('')"},
        }

        return settings

    def _write_settings(self, cloud, settings):
        suffix = ".aws_ec2.yml" if cloud == "aws" else ".gcp_compute.yml"

        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                prefix="oilscope-",
                suffix=suffix,
                delete=False,
            ) as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False, sort_keys=False)
                generated = handle.name
        except OSError as error:
            raise AnsibleParserError(
                f"could not write generated {cloud} inventory settings: {error}"
            ) from error

        return generated

    def _discover(self, cloud, loader, settings):
        from ansible.inventory.data import InventoryData
        from ansible.plugins.loader import inventory_loader

        delegate_name = DELEGATES[cloud]
        delegate = inventory_loader.get(delegate_name)
        if delegate is None:
            raise AnsibleParserError(
                f"the {delegate_name} inventory plugin is unavailable; install its collection"
            )

        generated = self._write_settings(cloud, settings)
        discovered = InventoryData()
        try:
            delegate.parse(discovered, loader, generated, cache=False)
        finally:
            try:
                os.unlink(generated)
            except OSError as error:
                display.vvv(f"could not remove {generated}: {error}")

        return discovered

    def _ssh_user(self, cloud, config):
        override = str(self.get_option("ssh_user") or "").strip()
        if override:
            return override

        if cloud == "aws":
            return "ubuntu"

        ssh_users = config.get("ssh_users")
        if not isinstance(ssh_users, dict) or not ssh_users:
            raise AnsibleParserError("the project configuration must define at least one SSH user")

        return sorted(ssh_users)[0]

    @staticmethod
    def _ssh_base_arguments(environment):
        if environment == "dev":
            host_key_arguments = [
                "-o",
                "StrictHostKeyChecking=no",
                "-o",
                "UserKnownHostsFile=/dev/null",
            ]
        else:
            host_key_arguments = ["-o", "StrictHostKeyChecking=accept-new"]

        return [*host_key_arguments, "-o", "IdentitiesOnly=yes"]

    def _ssh_private_key_file(self):
        configured = str(self.get_option("ssh_private_key_file") or "").strip()
        if not configured:
            return ""

        return os.path.abspath(os.path.expanduser(configured))

    def _connection_variables(
        self,
        cloud,
        config,
        virtual_machines,
        discovered,
        vm,
        is_bastion,
    ):
        environment = self._required_string(config, "environment")
        ssh_user = self._ssh_user(cloud, config)
        private_key_file = self._ssh_private_key_file()
        base_arguments = self._ssh_base_arguments(environment)
        common_arguments = list(base_arguments)

        if not is_bastion:
            matching_bastions = [
                candidate
                for candidate in virtual_machines.values()
                if "bastion" in candidate["tags"] and candidate["location"] == vm["location"]
            ]
            if len(matching_bastions) != 1:
                raise AnsibleParserError(
                    f"workload {vm['resource_name']!r} requires exactly one {cloud} "
                    f"bastion in location {vm['location']!r}"
                )

            bastion = matching_bastions[0]
            discovered_bastion = discovered.hosts.get(bastion["resource_name"])
            if discovered_bastion is None:
                raise AnsibleParserError(f"bastion {bastion['resource_name']!r} was not discovered")

            bastion_address = discovered_bastion.vars.get("oilscope_discovered_public_ip") or ""
            if not bastion_address:
                raise AnsibleParserError(
                    f"bastion {bastion['resource_name']!r} has no public IP address"
                )

            try:
                bastion_port = int(bastion["ssh_port"])
            except (KeyError, TypeError, ValueError) as error:
                raise AnsibleParserError(
                    f"bastion {bastion['resource_name']!r} must define an integer ssh_port"
                ) from error

            proxy_command = [
                "ssh",
                "-W",
                "%h:%p",
                "-q",
                "-p",
                str(bastion_port),
                *base_arguments,
            ]
            if private_key_file:
                proxy_command.extend(["-i", private_key_file])
            proxy_command.append(f"{ssh_user}@{bastion_address}")
            common_arguments.extend(["-o", f"ProxyCommand={shlex.join(proxy_command)}"])

        variables = {
            "ansible_user": ssh_user,
            "ansible_ssh_common_args": shlex.join(common_arguments),
        }
        if private_key_file:
            variables["ansible_ssh_private_key_file"] = private_key_file

        return variables

    def _add_hosts(self, inventory, cloud, config, virtual_machines, discovered):
        inventory.add_group(cloud)
        inventory.add_group("workloads")

        for vm in virtual_machines.values():
            for tag in vm["tags"]:
                inventory.add_group(tag)

        for name, vm in virtual_machines.items():
            resource_name = vm["resource_name"]
            discovered_host = discovered.hosts.get(resource_name)
            if discovered_host is None:
                display.vvv(f"configured {cloud} VM {resource_name} was not discovered")
                continue

            public_ip = discovered_host.vars.get("oilscope_discovered_public_ip") or ""
            internal_ip = self._required_string(vm, "internal_ip", f"VM {name!r}")
            is_bastion = "bastion" in vm["tags"]

            inventory.add_host(resource_name)
            inventory.add_child(cloud, resource_name)
            for tag in vm["tags"]:
                inventory.add_child(tag, resource_name)
            if not is_bastion:
                inventory.add_child("workloads", resource_name)

            host_variables = {
                "ansible_host": public_ip if is_bastion and public_ip else internal_ip,
                "internal_ip": internal_ip,
                "public_ip": public_ip,
                "oilscope_cloud": cloud,
                "oilscope_location": vm["location"],
                "oilscope_tags": vm["tags"],
                "oilscope_vm_name": name,
                **self._connection_variables(
                    cloud,
                    config,
                    virtual_machines,
                    discovered,
                    vm,
                    is_bastion,
                ),
            }

            if is_bastion:
                try:
                    bastion_ssh_port = int(vm["ssh_port"])
                except (KeyError, TypeError, ValueError) as error:
                    raise AnsibleParserError(
                        f"bastion VM {name!r} must define an integer ssh_port"
                    ) from error
                host_variables["ansible_port"] = bastion_ssh_port
                host_variables["bastion_ssh_port"] = bastion_ssh_port
            else:
                host_variables["ansible_port"] = 22

            for variable, value in host_variables.items():
                inventory.set_variable(resource_name, variable, value)
