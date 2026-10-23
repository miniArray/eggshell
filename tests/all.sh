#!/usr/bin/env nix-shell
#! nix-shell -i bash -p nix
set -euo pipefail
cd "$(dirname "$0")/.."
exec nix develop -c python3 tests/check_all.py "$@"
