# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) Push and Pray team
"""Derive per-cloud inventory settings from the shared project configuration JSON."""

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
short_description: OilScope inventory derived from the project configuration
version_added: "0.2.0"
author:
  - Push and Pray team
description:
  - Reads the project configuration JSON that Terraform also reads, works out
    which clouds actually host workloads, and hands each one to the discovery
    plugin that speaks to it - C(google.cloud.gcp_compute) for GCP and
    C(amazon.aws.aws_ec2) for AWS. Hosts from every cloud land in one inventory.
  - A cloud is skipped when it hosts no workload. Terraform applies the same
    rule - a bastion with nothing to reach is not built, so there is nothing to
    discover either.
  - Every host gets C(oilscope_cloud) from the resource's own C(cloud) label or
    tag. Workloads use it to pick the bastion of their own cloud, because
    without cross-cloud networking a bastion cannot reach the other provider.
  - When the configuration runs the database as a managed service, the plugin
    also asks the cloud hosting the C(infra) VM where that database is - the
    Private Service Connect endpoint address on GCP, the RDS endpoint on AWS -
    and publishes it to every host as C(oilscope_managed_database_host) and
    C(oilscope_managed_database_port). Terraform state is never read.
  - The wrapper exists because neither discovery plugin reads that file, and
    neither evaluates Jinja in its own configuration - a template expression
    there reaches the API as literal text.
extends_documentation_fragment:
  - inventory_cache
options:
  plugin:
    description:
      - Token that identifies this plugin. Must be
        C(oilscope.platform.oilscope_cloud).
    type: str
    required: true
    choices:
      - oilscope.platform.oilscope_cloud
  project_config_path:
    description:
      - Path to the project configuration JSON. Absolute is used as given;
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
  workload_ssh_port:
    description:
      - Port the workload VMs listen on. The Terraform firewall rules open 22
        and nothing else, so a bastion's port must not apply to them.
    type: int
    default: 22
  bastion_connect_port:
    description:
      - Overrides the port used to reach every bastion, for the window in which
        a freshly created host still listens on 22. Leave unset to use the port
        the project-wide bastion block declares.
    type: int
    required: false
    env:
      - name: OILSCOPE_BASTION_CONNECT_PORT
  bastion_role:
    description:
      - Value of C(role) identifying a bastion in the instance label or tag.
        Terraform stamps it on the bastion it derives from the C(bastion)
        block; no entry under C(vms) carries it.
    type: str
    default: bastion
  auth_kind:
    description:
      - Passed straight through to C(google.cloud.gcp_compute). Ignored by AWS,
        which authenticates the way boto3 does.
    type: str
    default: application
  discover_database:
    description:
      - Whether to look the managed database endpoint up. Off, the variables
        are not set and a play that needs them must be given
        C(oilscope_managed_database_host) another way, for example with C(-e).
        Only read when C(database.mode) is C(managed).
    type: bool
    default: true
    env:
      - name: OILSCOPE_DISCOVER_DATABASE
requirements:
  - google.cloud collection, google-auth and requests, for GCP discovery
  - amazon.aws collection and boto3, for AWS discovery
  - the Compute Engine API (GCP) or C(rds:DescribeDBInstances) (AWS) for the
    managed database lookup
notes:
  - GCP authenticates with Application Default Credentials. Run
    C(gcloud auth application-default login) on the controller first.
  - AWS authenticates through the standard boto3 chain - environment variables,
    a shared credentials file, or an instance role.
"""

EXAMPLES = r"""
# inventory/oilscope.yml - the path comes from OILSCOPE_PROJECT_CONFIG or the
# option default, so it is deliberately not set here.
plugin: oilscope.platform.oilscope_cloud
cache: true
cache_plugin: ansible.builtin.jsonfile
cache_connection: ~/.cache/oilscope-inventory
cache_timeout: 300
"""

DELEGATES = {
    "gcp": "google.cloud.gcp_compute",
    "aws": "amazon.aws.aws_ec2",
}

COLLECTIONS = {
    "gcp": "google.cloud",
    "aws": "amazon.aws",
}

display = Display()


def plain(value):
    return str(value)


class InventoryModule(BaseInventoryPlugin, Cacheable):
    NAME = "oilscope.platform.oilscope_cloud"

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

        self._publish_database(inventory, config)

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
                f"could not load the project configuration at {config_path}: {error}"
            ) from error

        if not isinstance(config, dict):
            raise AnsibleParserError(
                f"the project configuration at {config_path} must contain a JSON object"
            )

        return config

    def _require(self, mapping, key, where):
        value = mapping.get(key)

        if not value or not isinstance(value, str):
            raise AnsibleParserError(
                f"the project configuration must define a non-empty string {key!r} in {where}"
            )

        return value

    def _vms(self, config):
        vms = config.get("vms")

        if not isinstance(vms, dict):
            raise AnsibleParserError("the project configuration must define a 'vms' object")

        return vms

    def _placement(self, config, vm):
        return vm.get("cloud") or self._require(config, "default_cloud", "the configuration root")

    # ------------------------------------------------------------------ clouds

    def _active_clouds(self, config):
        declared = config.get("clouds")

        if not isinstance(declared, dict):
            raise AnsibleParserError("the project configuration must define a 'clouds' object")

        active = set()

        # vms holds workloads only; the bastion of each active cloud is derived
        # from the top-level 'bastion' block, so it never appears here.
        for name, vm in self._vms(config).items():
            if not isinstance(vm, dict):
                raise AnsibleParserError(f"the {name!r} VM must be a JSON object")

            active.add(self._placement(config, vm))

        for cloud in sorted(active):
            if cloud not in declared:
                raise AnsibleParserError(
                    f"workloads are placed on {cloud!r} but 'clouds' declares no profile for it"
                )

            if cloud not in DELEGATES:
                raise AnsibleParserError(
                    f"no discovery plugin is known for cloud {cloud!r}; "
                    f"supported clouds are {', '.join(sorted(DELEGATES))}"
                )

        return sorted(active)

    def _bastion_ssh_port(self, config):
        """Port from the project-wide bastion block.

        Every active cloud runs the same bastion specification, so this is one
        value for the whole project rather than one per cloud.
        """
        bastion = config.get("bastion")

        if not isinstance(bastion, dict):
            raise AnsibleParserError("the project configuration must define a 'bastion' object")

        try:
            return int(bastion["ssh_port"])
        except KeyError as missing:
            raise AnsibleParserError("the 'bastion' block must define ssh_port") from missing
        except (TypeError, ValueError) as port_error:
            raise AnsibleParserError(
                "the 'bastion' block must define an integer ssh_port"
            ) from port_error

    def _connect_ports(self, config, cloud):
        """(bastion connect port, bastion final port, workload port).

        The connect port honours the bootstrap override; the final port never
        does. The override says how to reach the bastion *now*, while the final
        port is what the bastion role configures - conflating them made the role
        write the bootstrap port into sshd and lock the bastion out once the
        bootstrap firewall rule was removed.
        """
        final_port = self._bastion_ssh_port(config)
        override = self.get_option("bastion_connect_port")
        connect_port = int(override) if override else final_port

        return connect_port, final_port, int(self.get_option("workload_ssh_port"))

    # ---------------------------------------------------------------- settings

    def _build_settings(self, config, cloud):
        builders = {"gcp": self._gcp_settings, "aws": self._aws_settings}

        return builders[cloud](config, cloud)

    def _gcp_settings(self, config, cloud):
        profile = config["clouds"][cloud]
        project_id = self._require(profile, "project_id", f"clouds.{cloud}")
        zone = self._require(profile, "zone", f"clouds.{cloud}")
        bastion_role = plain(self.get_option("bastion_role"))
        bastion_port, bastion_final_port, workload_port = self._connect_ports(config, cloud)
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
            "groups": {"workloads": f"labels.role is defined and labels.role != '{bastion_role}'"},
            "compose": {
                "internal_ip": private,
                "public_ip": f"{public} if {has_public} else ''",
                "ansible_host": f"{public} if {is_bastion} else {private}",
                "ansible_port": f"{bastion_port} if {is_bastion} else {workload_port}",
                "oilscope_role": "labels.role | default('')",
                "oilscope_cloud": f"'{cloud}'",
                "oilscope_ssh_port": f"{bastion_final_port} if {is_bastion} else {workload_port}",
            },
        }

    def _aws_settings(self, config, cloud):
        profile = config["clouds"][cloud]
        region = self._require(profile, "region", f"clouds.{cloud}")
        bastion_role = plain(self.get_option("bastion_role"))
        bastion_port, bastion_final_port, workload_port = self._connect_ports(config, cloud)

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
            "groups": {"workloads": f"tags.role is defined and tags.role != '{bastion_role}'"},
            "compose": {
                "internal_ip": private,
                "public_ip": public,
                "ansible_host": f"{public} if {is_bastion} else {private}",
                "ansible_port": f"{bastion_port} if {is_bastion} else {workload_port}",
                "oilscope_role": "tags.role | default('')",
                "oilscope_cloud": f"'{cloud}'",
                "oilscope_ssh_port": f"{bastion_final_port} if {is_bastion} else {workload_port}",
            },
        }

    # ---------------------------------------------------------------- database

    def _database_managed(self, config):
        database = config.get("database")

        if database is None:
            return False

        if not isinstance(database, dict):
            raise AnsibleParserError("the project configuration's 'database' must be a JSON object")

        return database.get("mode", "self-hosted") == "managed"

    def _infra_cloud(self, config):
        """The cloud hosting the infra VM - the one that builds the managed database."""
        for vm in self._vms(config).values():
            if isinstance(vm, dict) and vm.get("role") == "infra":
                return self._placement(config, vm)

        raise AnsibleParserError(
            "the database is managed but no VM under 'vms' has the role 'infra'"
        )

    def _resource_prefix(self, config):
        name_prefix = self._require(config, "name_prefix", "the configuration root")
        environment = self._require(config, "environment", "the configuration root")

        return f"{name_prefix}-{environment}"

    def _publish_database(self, inventory, config):
        """Hand every host the managed database endpoint, when there is one.

        Terraform knows the address, but its state is not something Ansible
        should have to read. The endpoint carries a name derived from the same
        configuration, so it can be asked for directly.
        """
        if not self._database_managed(config) or not self.get_option("discover_database"):
            return

        cloud = self._infra_cloud(config)
        lookups = {"gcp": self._gcp_database, "aws": self._aws_database}
        host, port = lookups[cloud](config)

        inventory.set_variable("all", "oilscope_managed_database_host", host)
        inventory.set_variable("all", "oilscope_managed_database_port", port)

        display.vvv(f"managed database on {cloud}: {host}:{port}")

    def _gcp_database(self, config):
        try:
            import google.auth
            from google.auth.transport.requests import AuthorizedSession
        except ImportError as error:
            raise AnsibleParserError(
                f"the managed database lookup on GCP needs google-auth and requests: {error}"
            ) from error

        profile = config["clouds"]["gcp"]
        project_id = self._require(profile, "project_id", "clouds.gcp")
        region = self._require(profile, "region", "clouds.gcp")
        name = f"{self._resource_prefix(config)}-database-endpoint"

        credentials, _ = google.auth.default(
            scopes=["https://www.googleapis.com/auth/compute.readonly"]
        )
        session = AuthorizedSession(credentials)
        response = session.get(
            "https://compute.googleapis.com/compute/v1"
            f"/projects/{project_id}/regions/{region}/addresses/{name}",
            timeout=30,
        )

        if response.status_code == 404:
            raise AnsibleParserError(
                f"the managed database endpoint {name!r} does not exist in {project_id}/{region}; "
                "apply the Terraform configuration first, or set discover_database to false"
            )

        if response.status_code != 200:
            raise AnsibleParserError(
                f"could not read the managed database endpoint {name!r}: "
                f"HTTP {response.status_code} {response.text[:200]}"
            )

        address = response.json().get("address")

        if not address:
            raise AnsibleParserError(f"the endpoint {name!r} carries no address yet")

        return address, int(config.get("service_ports", {}).get("postgresql", 5432))

    def _aws_database(self, config):
        try:
            import boto3
            from botocore.exceptions import BotoCoreError, ClientError
        except ImportError as error:
            raise AnsibleParserError(
                f"the managed database lookup on AWS needs boto3: {error}"
            ) from error

        profile = config["clouds"]["aws"]
        region = self._require(profile, "region", "clouds.aws")
        identifier = f"{self._resource_prefix(config)}-database"

        try:
            response = boto3.client("rds", region_name=region).describe_db_instances(
                DBInstanceIdentifier=identifier
            )
        except ClientError as error:
            if error.response.get("Error", {}).get("Code") == "DBInstanceNotFound":
                raise AnsibleParserError(
                    f"the managed database {identifier!r} does not exist in {region}; "
                    "apply the Terraform configuration first, or set discover_database to false"
                ) from error

            raise AnsibleParserError(
                f"could not describe the managed database {identifier!r}: {error}"
            ) from error
        except BotoCoreError as error:
            raise AnsibleParserError(
                f"could not describe the managed database {identifier!r}: {error}"
            ) from error

        endpoint = response["DBInstances"][0].get("Endpoint") or {}

        if not endpoint.get("Address"):
            raise AnsibleParserError(
                f"the managed database {identifier!r} has no endpoint yet; "
                "it is still being created"
            )

        return endpoint["Address"], int(endpoint.get("Port", 5432))

    def _write_settings(self, settings, cloud):
        digest = hashlib.sha256(json.dumps(settings, sort_keys=True).encode("utf-8")).hexdigest()
        generated = os.path.join(tempfile.gettempdir(), f"oilscope-{digest[:16]}.{cloud}.yml")

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
