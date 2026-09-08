# Observability agent

Installs Google Cloud Ops Agent on GCP inventory hosts. The agent keeps its
built-in host-metrics pipeline and adds a file receiver for Docker's JSON log
files under `/var/lib/docker/containers`.

The role is selected from the neutral `oilscope_cloud` inventory variable. It
currently skips non-GCP hosts; a provider-specific task file can be added for
AWS without changing workload roles.
