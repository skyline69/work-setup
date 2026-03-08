#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
printf '[WARN] quickshell/install.sh is deprecated; delegating to ../install.sh\n' >&2
exec "$SCRIPT_DIR/../install.sh" "$@"
