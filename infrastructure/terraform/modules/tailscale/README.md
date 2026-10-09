# Tailscale module

Owns the shared OilScope tailnet resources and renders first-boot configuration
for the cloud VM modules.

The module derives active clouds, subnet-router selection, hostnames, and
advertised routes from the decoded project configuration. The root module only
supplies that configuration and the resolved Azure VNet CIDRs. This module:

- validates the multi-cloud Tailscale topology and settings;
- optionally manages the complete Tailscale policy;
- creates a short-lived, reusable, pre-authorized bootstrap key;
- renders the official Tailscale cloud-init module for each VM;
- returns sensitive cloud-init payloads keyed by logical VM name.

Provider API credentials are read by the root Tailscale provider from
environment variables. No credential is accepted as a normal module input.
