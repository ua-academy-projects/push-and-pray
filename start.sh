#!/usr/bin/env bash
set -euo pipefail

vagrant up
./status.sh
