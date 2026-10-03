# Azure identity module

Creates the runtime identity of one VM: a user-assigned managed identity, and
nothing else.

Separate from the [VM module](../vm/README.md) for the same reasons as on the
other clouds: the identity outlives the VM, and the role assignments that grant
it access to secrets are written by `secrets.tf`, which has no business
reaching into compute.

User-assigned rather than the VM's own system-assigned identity, because a
system-assigned one is deleted with the VM and recreated with a new principal
on replacement - every grant would have to follow it.

## Naming

The identity carries the VM's name. That is load-bearing: `resolve_secrets`
asks the metadata service for a token of the identity
`<name_prefix>-<environment>-rg/.../userAssignedIdentities/<VM name>`. A VM can
hold several identities, and the metadata service picks one arbitrarily when it
is not told which.

## Outputs

| Name | Description |
| --- | --- |
| `identity`, `id` | Resource ID - the counterpart of a service-account email or a role ARN; what a VM and the metadata service take |
| `principal_id` | Object ID of its service principal - what a role assignment takes |
| `client_id`, `name` | The remaining identifiers |

## License

GPL-2.0-or-later
