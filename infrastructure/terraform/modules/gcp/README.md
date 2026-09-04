# GCP stack module

This module owns the complete GCP stack. Its nested `config` module interprets
the shared JSON and resolves GCP profiles; `network` and `vm` contain the
provider resources. Nothing outside `modules/gcp` contains GCP implementation
details.

If no VM selects GCP, the module creates no resources and returns empty maps.
Its vms output uses the same provider-neutral shape as modules/aws.
