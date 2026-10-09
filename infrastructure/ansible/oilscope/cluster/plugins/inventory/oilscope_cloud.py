# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Derive per-cloud inventory settings from the shared cluster configuration JSON."""

import hashlib
import json
import os
import tempfile

from ansible.errors import AnsibleError, AnsibleParserError
from ansible.plugins.inventory import BaseInventoryPlugin, Cacheable
from ansible.utils.display import Display

try:
    import yaml

    HAS_YAML = True
except ImportError:  # pragma: no cover - PyYAML ships with ansible-core
    HAS_YAML = False

# DO NOT DELETE BECAUSE PLUGIN WILL FAIL
DOCUMENTATION = r"""
name: oilscope_cloud
short_description: OilScope inventory derived from the cluster configuration
version_added: "0.2.0"
author:
  - Push and Pray team
description:
  - Reads the cluster configuration JSON that Terraform also reads, works out
    which clouds actually host nodes, and hands each one to the discovery
    plugin that speaks to it - C(google.cloud.gcp_compute) for GCP,
    C(amazon.aws.aws_ec2) for AWS and C(azure.azcollection.azure_rm) for
    Azure. Hosts from every cloud land in one inventory.
  - A node's cloud is its own C(cloud), or C(default_cloud) when it sets none -
    the same rule Terraform applies.
  - A cloud is skipped when it hosts no node. Terraform applies the same rule -
    a bastion with nothing to route for is not built, so there is nothing to
    discover either.
  - Every host lands in the group of its C(role) label or tag - C(bastion),
    C(k3s_server), C(k3s_agent) - and every node also in C(nodes). Every host
    gets C(oilscope_cloud) from the resource's own C(cloud) label or tag.
    Terraform state is never read.
  - The wrapper exists because no discovery plugin reads that file, and none
    evaluates Jinja in its own configuration - a template expression there
    reaches the API as literal text.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token that identifies this plugin. Must be
        C(oilscope.cluster.oilscope_cloud).
    type: str
    required: true
    choices:
      - oilscope.cluster.oilscope_cloud
  project_config_path:
    description:
      - Path to the cluster configuration JSON. Absolute is used as given;
        relative is tried against the working directory, then against this
        file's directory.
      - Set C(OILSCOPE_PROJECT_CONFIG) for a configuration kept elsewhere. A
        value written into the inventory file wins over the environment, so
        leave the key out to make the variable effective.
    type: str
    required: false
    default: ../../terraform/env/dev.json
    env:
      - name: OILSCOPE_PROJECT_CONFIG
  node_ssh_port:
    description:
      - Port the nodes listen on. The Terraform firewall rules open 22 and
        nothing else, so a bastion's port must not apply to them.
    type: int
    default: 22
  bastion_connect_port:
    description:
      - Overrides the port used to reach every bastion, for the window in which
        a freshly created host still listens on 22. Leave unset to use the port
        the project-wide bastion block declares, or 22 when it declares none.
    type: int
    required: false
    env:
      - name: OILSCOPE_BASTION_CONNECT_PORT
  bastion_role:
    description:
      - Value of C(role) identifying a bastion in the instance label or tag.
        Terraform stamps it on the bastion it derives from the C(bastion)
        block; no entry under C(nodes) carries it.
    type: str
    default: bastion
  auth_kind:
    description:
      - Passed straight through to C(google.cloud.gcp_compute). Ignored by AWS,
        which authenticates the way boto3 does.
    type: str
    default: application
  azure_auth_source:
    description:
      - Passed straight through to C(azure.azcollection.azure_rm) as its
        C(auth_source). C(auto) tries a service principal from the environment
        first and falls back to the C(az login) session.
    type: str
    default: auto
    choices:
      - auto
      - cli
      - env
      - credential_file
      - msi
requirements:
  - google.cloud collection, google-auth and requests, for GCP discovery
  - amazon.aws collection and boto3, for AWS discovery
  - azure.azcollection collection and the Azure SDK its requirements.txt lists,
    for Azure discovery
notes:
  - GCP authenticates with Application Default Credentials. Run
    C(gcloud auth application-default login) on the controller first.
  - AWS authenticates through the standard boto3 chain - environment variables,
    a shared credentials file, or an instance role.
  - Azure authenticates with a service principal from the environment or the
    C(az login) session. Every Azure resource sits in the resource group
    C(<name_prefix>-<environment>-rg) of C(clouds.azure.subscription_id).
"""

EXAMPLES = r"""
# inventory/oilscope.yml - the path comes from OILSCOPE_PROJECT_CONFIG or the
# option default, so it is deliberately not set here.
plugin: oilscope.cluster.oilscope_cloud
cache: true
cache_plugin: ansible.builtin.jsonfile
cache_connection: ~/.cache/oilscope-inventory
cache_timeout: 300
"""

DELEGATES = {
    "gcp": "google.cloud.gcp_compute",
    "aws": "amazon.aws.aws_ec2",
    "azure": "azure.azcollection.azure_rm",
}

COLLECTIONS = {
    "gcp": "google.cloud",
    "aws": "amazon.aws",
    "azure": "azure.azcollection",
}

# Each delegate claims a settings file only by the end of its name, and
# azure_rm refuses any other name outright instead of passing.
SETTINGS_SUFFIXES = {
    "gcp": "gcp.yml",
    "aws": "aws.yml",
    "azure": "azure_rm.yml",
}

display = Display()


def plain(value):
    return str(value)


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.cluster.oilscope_cloud"

    def verify_file(self, path):
        return super().verify_file(path) and path.endswith(("oilscope.yml", "oilscope.yaml"))

    def parse(self, inventory, loader, path, cache=True):
        super().parse(inventory, loader, path, cache=cache)
        self._read_config_data(path)

        if not HAS_YAML:
            raise AnsibleParserError("the oilscope_cloud inventory plugin requires PyYAML")

        config = self._load_project_config(path)

        for cloud in self._active_clouds(config):
            settings = self._build_settings(config, cloud)
            generated = self._write_settings(settings, cloud)

            try:
                self._delegate(inventory, loader, generated, cache, cloud)
            finally:
                try:
                    os.unlink(generated)
                except OSError as cleanup_error:
                    display.vvv(f"could not remove {generated}: {cleanup_error}")

    # ------------------------------------------------------------------ config

    def _resolve_config_path(self, path):
        configured = plain(self.get_option("project_config_path"))

        if os.path.isabs(configured):
            return os.path.normpath(configured)

        from_cwd = os.path.abspath(configured)

        if os.path.isfile(from_cwd):
            return from_cwd

        beside = os.path.join(os.path.dirname(os.path.abspath(path)), configured)
        return os.path.normpath(beside)

    def _load_project_config(self, path):
        config_path = self._resolve_config_path(path)

        try:
            with open(config_path, "rb") as handle:
                config = json.load(handle)
        except (OSError, ValueError) as error:
            raise AnsibleParserError(
                f"could not load the cluster configuration at {config_path}: {error}"
            ) from error

        if not isinstance(config, dict):
            raise AnsibleParserError(
                f"the cluster configuration at {config_path} must contain a JSON object"
            )

        return config

    def _require(self, mapping, key, where):
        value = mapping.get(key)

        if not value or not isinstance(value, str):
            raise AnsibleParserError(
                f"the cluster configuration must define a non-empty string {key!r} in {where}"
            )

        return value

    def _nodes(self, config):
        nodes = config.get("nodes")

        if not isinstance(nodes, dict):
            raise AnsibleParserError(
                "the cluster configuration must define a 'nodes' object; a configuration"
                " with 'vms' is the Docker Compose layout this plugin no longer reads"
            )

        return nodes

    def _placement(self, config, node):
        """The node's own cloud, else default_cloud - the rule Terraform applies too."""
        return node.get("cloud") or self._require(config, "default_cloud", "the configuration root")

    # ------------------------------------------------------------------ clouds

    def _active_clouds(self, config):
        declared = config.get("clouds")

        if not isinstance(declared, dict):
            raise AnsibleParserError("the cluster configuration must define a 'clouds' object")

        active = set()

        # nodes holds cluster nodes only; the bastion of each active cloud is
        # derived from the top-level 'bastion' block, so it never appears here.
        for name, node in self._nodes(config).items():
            if not isinstance(node, dict):
                raise AnsibleParserError(f"the {name!r} node must be a JSON object")

            active.add(self._placement(config, node))

        for cloud in sorted(active):
            if cloud not in declared:
                raise AnsibleParserError(
                    f"nodes are placed on {cloud!r} but 'clouds' declares no profile for it"
                )

            if cloud not in DELEGATES:
                raise AnsibleParserError(
                    f"no discovery plugin is known for cloud {cloud!r}; "
                    f"supported clouds are {', '.join(sorted(DELEGATES))}"
                )

        return sorted(active)

    def _bastion_ssh_port(self, config):
        """Port from the project-wide bastion block, 22 when it names none.

        Every active cloud runs the same bastion specification, so this is one
        value for the whole project rather than one per cloud.
        """
        bastion = config.get("bastion")

        if not isinstance(bastion, dict):
            raise AnsibleParserError("the cluster configuration must define a 'bastion' object")

        try:
            return int(bastion.get("ssh_port", 22))
        except (TypeError, ValueError) as port_error:
            raise AnsibleParserError(
                "the 'bastion' block must define an integer ssh_port"
            ) from port_error

    def _connect_ports(self, config, cloud):
        """(bastion connect port, bastion final port, node port).

        The connect port honours the bootstrap override; the final port never
        does. The override says how to reach the bastion *now*, while the final
        port is what the bastion role configures - conflating them made the role
        write the bootstrap port into sshd and lock the bastion out once the
        bootstrap firewall rule was removed.
        """
        final_port = self._bastion_ssh_port(config)
        override = self.get_option("bastion_connect_port")
        connect_port = int(override) if override else final_port

        return connect_port, final_port, int(self.get_option("node_ssh_port"))

    # ---------------------------------------------------------------- settings

    def _build_settings(self, config, cloud):
        builders = {
            "gcp": self._gcp_settings,
            "aws": self._aws_settings,
            "azure": self._azure_settings,
        }

        return builders[cloud](config, cloud)

    def _gcp_settings(self, config, cloud):
        profile = config["clouds"][cloud]
        project_id = self._require(profile, "project_id", f"clouds.{cloud}")
        zone = self._require(profile, "zone", f"clouds.{cloud}")
        bastion_role = plain(self.get_option("bastion_role"))
        bastion_port, bastion_final_port, node_port = self._connect_ports(config, cloud)
        name_prefix = self._require(config, "name_prefix", "the configuration root")
        environment = self._require(config, "environment", "the configuration root")

        is_bastion = f"labels.role | default('') == '{bastion_role}'"
        has_public = "networkInterfaces[0].accessConfigs | default([])"
        public = "networkInterfaces[0].accessConfigs[0].natIP"
        private = "networkInterfaces[0].networkIP"

        return {
            "plugin": DELEGATES[cloud],
            "projects": [plain(project_id)],
            "zones": [plain(zone)],
            "filters": [
                f"labels.application = {name_prefix}",
                f"labels.environment = {environment}",
                f"labels.cloud = {cloud}",
            ],
            "auth_kind": plain(self.get_option("auth_kind")),
            "hostnames": ["name"],
            "vars_prefix": f"{cloud}_",
            "keyed_groups": [{"key": "labels.role", "prefix": "", "separator": ""}],
            "groups": {"nodes": f"labels.role is defined and labels.role != '{bastion_role}'"},
            "compose": {
                "internal_ip": private,
                "public_ip": f"{public} if {has_public} else ''",
                "ansible_host": f"{public} if {is_bastion} else {private}",
                "ansible_port": f"{bastion_port} if {is_bastion} else {node_port}",
                "oilscope_role": "labels.role | default('')",
                "oilscope_cloud": f"'{cloud}'",
                "oilscope_ssh_port": f"{bastion_final_port} if {is_bastion} else {node_port}",
            },
        }

    def _aws_settings(self, config, cloud):
        profile = config["clouds"][cloud]
        region = self._require(profile, "region", f"clouds.{cloud}")
        bastion_role = plain(self.get_option("bastion_role"))
        bastion_port, bastion_final_port, node_port = self._connect_ports(config, cloud)

        is_bastion = f"tags.role | default('') == '{bastion_role}'"
        public = "public_ip_address | default('')"
        private = "private_ip_address"

        return {
            "plugin": DELEGATES[cloud],
            "regions": [plain(region)],
            "filters": {
                "tag:application": self._require(config, "name_prefix", "the configuration root"),
                "tag:environment": self._require(config, "environment", "the configuration root"),
                "tag:cloud": cloud,
                "instance-state-name": ["pending", "running"],
            },
            "hostnames": ["tag:Name"],
            "vars_prefix": f"{cloud}_",
            "keyed_groups": [{"key": "tags.role", "prefix": "", "separator": ""}],
            "groups": {"nodes": f"tags.role is defined and tags.role != '{bastion_role}'"},
            "compose": {
                "internal_ip": private,
                "public_ip": public,
                "ansible_host": f"{public} if {is_bastion} else {private}",
                "ansible_port": f"{bastion_port} if {is_bastion} else {node_port}",
                "oilscope_role": "tags.role | default('')",
                "oilscope_cloud": f"'{cloud}'",
                "oilscope_ssh_port": f"{bastion_final_port} if {is_bastion} else {node_port}",
            },
        }

    def _azure_settings(self, config, cloud):
        profile = config["clouds"][cloud]
        subscription_id = self._require(profile, "subscription_id", f"clouds.{cloud}")
        bastion_role = plain(self.get_option("bastion_role"))
        bastion_port, bastion_final_port, node_port = self._connect_ports(config, cloud)
        name_prefix = self._require(config, "name_prefix", "the configuration root")
        environment = self._require(config, "environment", "the configuration root")

        # azure_rm filters nothing on the API side, so the labels the other two
        # clouds send as a query become an include condition here. A tag the VM
        # does not carry must not raise, or the host would be skipped silently
        # for the wrong reason.
        matches = " and ".join(
            f"tags.{key} | default('') == '{value}'"
            for key, value in (
                ("application", name_prefix),
                ("environment", environment),
                ("cloud", cloud),
            )
        )

        is_bastion = f"tags.role | default('') == '{bastion_role}'"
        # azure_rm lists addresses; the documented public_ipv4_addresses was
        # renamed to public_ipv4_address and kept as a list.
        public = "public_ipv4_address | first | default('')"
        private = "private_ipv4_addresses | first"

        return {
            "plugin": DELEGATES[cloud],
            "auth_source": plain(self.get_option("azure_auth_source")),
            "subscription_id": plain(subscription_id),
            "include_vm_resource_groups": [self._azure_resource_group(config)],
            "include_host_filters": [matches],
            "hostnames": ["name"],
            "keyed_groups": [{"key": "tags.role", "prefix": "", "separator": ""}],
            "conditional_groups": {
                "nodes": f"tags.role is defined and tags.role != '{bastion_role}'"
            },
            "hostvar_expressions": {
                "internal_ip": private,
                "public_ip": public,
                "ansible_host": f"({public}) if {is_bastion} else {private}",
                "ansible_port": f"{bastion_port} if {is_bastion} else {node_port}",
                "oilscope_role": "tags.role | default('')",
                "oilscope_cloud": f"'{cloud}'",
                "oilscope_ssh_port": f"{bastion_final_port} if {is_bastion} else {node_port}",
            },
        }

    def _azure_resource_group(self, config):
        """The one resource group every Azure resource of this environment sits in.

        Derived rather than configured, the way every other resource name is.
        """
        return f"{self._resource_prefix(config)}-rg"

    def _resource_prefix(self, config):
        name_prefix = self._require(config, "name_prefix", "the configuration root")
        environment = self._require(config, "environment", "the configuration root")

        return f"{name_prefix}-{environment}"

    def _write_settings(self, settings, cloud):
        digest = hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()
        generated = os.path.join(
            tempfile.gettempdir(), f"oilscope-{digest[:16]}.{SETTINGS_SUFFIXES[cloud]}"
        )

        try:
            with open(generated, "w") as handle:
                yaml.safe_dump(settings, handle, default_flow_style=False)
        except OSError as write_error:
            raise AnsibleParserError(
                f"could not write the generated {cloud} settings to {generated}: {write_error}"
            ) from write_error

        return generated

    def _delegate(self, inventory, loader, generated, cache, cloud):
        from ansible.plugins.loader import inventory_loader

        name = DELEGATES[cloud]
        delegate = inventory_loader.get(name)

        if delegate is None:
            raise AnsibleParserError(
                f"the {name} inventory plugin is unavailable; "
                f"install the {COLLECTIONS[cloud]} collection"
            )

        for option in ("cache", "cache_plugin", "cache_connection", "cache_timeout"):
            try:
                delegate.set_option(option, self.get_option(option))
            except (AnsibleError, KeyError) as option_error:
                display.vvv(f"{name} rejected the {option} option: {option_error}")

        delegate.parse(inventory, loader, generated, cache=cache)
