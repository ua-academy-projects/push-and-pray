#!/usr/bin/env bash

set -Eeuo pipefail

printf 'WARNING: mirror-managed-images.sh is deprecated; promoting all deployment images.\n' >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/promote-cloud-images.sh" "$@"
