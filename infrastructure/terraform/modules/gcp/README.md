# GCP stack module

This module reads the shared project configuration, selects VMs whose effective
cloud is gcp, resolves abstract profiles through clouds.gcp dictionaries, and
owns all GCP-specific APIs, networking, compute, identity and secret resources.

If no VM selects GCP, the module creates no resources and returns empty maps.
Its vms output uses the same provider-neutral shape as modules/aws.
