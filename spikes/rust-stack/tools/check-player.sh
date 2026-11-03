#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils git nix
set -euo pipefail
export NIX_CONFIG='builders ='
test "$(hostname)" = aka
nix config show | grep '^builders ='
cd spikes/rust-stack/player
# Lock generation is intentionally remote. Source and assets never enter a shared cache.
nix develop --accept-flake-config -c cargo generate-lockfile
nix develop -c cargo fmt
nix develop -c cargo test --locked
nix develop -c cargo clippy --locked --all-targets -- -D warnings
nix develop -c cargo fmt -- --check
printf 'RUST_PLAYER_CHECK_DONE core_api_commit=%s core_tree=%s\n' "$(git log -1 --format=%H -- ../core)" "$(git rev-parse HEAD:spikes/rust-stack/core)"
