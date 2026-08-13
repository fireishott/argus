#!/usr/bin/env bash
# Argus local launcher. Configuration belongs in config/config.yaml.
# Put secrets in your service manager or a local environment file, never here.
set -euo pipefail

cd "$(dirname "$0")"
exec .venv/bin/python main.py "$@"
