#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# Preserve complete command output independently of the managed-process registry.
set -euo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
label=${1:?evidence label required}
shift
[[ "$label" =~ ^[a-zA-Z0-9_.-]+$ ]]
root="$HOME/eggshell-remote/artifacts/full-rust-ab/core/evidence"
mkdir -p "$root"
log="$root/$label.log"
if [[ -e "$log" ]]; then printf 'Refusing to overwrite evidence: %s\n' "$log" >&2; exit 1; fi
(set -o noclobber; : > "$log")
exec > >(tee -a "$log") 2>&1
printf 'EVIDENCE_BEGIN source=%s artifact=%s command=' "$(git rev-parse HEAD)" "$log"
printf '%q ' "$@"
printf '\n'
status=0
"$@" || status=$?
printf 'EVIDENCE_DONE source=%s exit=%s artifact=%s\n' "$(git rev-parse HEAD)" "$status" "$log"
exit "$status"
