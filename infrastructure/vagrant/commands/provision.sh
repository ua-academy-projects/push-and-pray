#!/usr/bin/env bash

set -Eeuo pipefail

printf 'Vagrant deployment is unsupported for issue #58. Use the cloud deployment path with Secret Manager.\n' >&2
exit 1
