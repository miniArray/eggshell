#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash python3 openssh coreutils
# Optional integration check. Requires an existing deployment and no running instance.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
if python3 tools/device.py status; then
  echo 'Stop the existing instance before running this check' >&2
  exit 1
else
  code=$?
  [[ "$code" == 3 ]] || exit "$code"
fi
mkdir -p build/device-checks
label=stop-check-$(date +%s)
trap 'python3 tools/device.py stop' EXIT
python3 tools/device.py run bench "$label" 60 opengl3_es
python3 tools/device.py status
if python3 tools/device.py deploy > build/device-checks/deploy.txt 2>&1; then
  echo 'FAIL: deploy replaced a running instance' >&2
  exit 1
fi
grep -q 'Stop Eggshell before deploying' build/device-checks/deploy.txt
if python3 tools/device.py run bench "$label" 60 opengl3_es > build/device-checks/concurrent.txt 2>&1; then
  echo 'FAIL: a second instance started' >&2
  exit 1
fi
grep -q 'Eggshell is already running' build/device-checks/concurrent.txt
python3 tools/device.py stop
if python3 tools/device.py status; then
  echo 'FAIL: instance still running' >&2
  exit 1
else
  code=$?
  [[ "$code" == 3 ]] || exit "$code"
fi
if python3 tools/device.py run bench "$label" 60 opengl3_es > build/device-checks/reused.txt 2>&1; then
  echo 'FAIL: reused a diagnostic label' >&2
  exit 1
fi
grep -q 'Use a new log label' build/device-checks/reused.txt
trap - EXIT
python3 tools/device.py probe
echo 'PASS: start/status/stop, concurrent-start guard, deploy guard, reused-label guard'
