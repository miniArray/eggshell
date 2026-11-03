#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils nix ruff shellcheck
set -euo pipefail
export NIX_CONFIG='builders ='
[[ $(hostname) == aka ]]
ruff check --select I --fix spikes/rust-stack/tools/{generate-real-screens,audit-real-screens,inspect-real-screens,bundle-player}.py
ruff format spikes/rust-stack/tools/{generate-real-screens,audit-real-screens,inspect-real-screens,bundle-player}.py
ruff check spikes/rust-stack/tools/{generate-real-screens,audit-real-screens,inspect-real-screens,bundle-player}.py
shellcheck --shell=bash spikes/rust-stack/tools/launch-owned-stress.sh spikes/rust-stack/tools/check-real-screens.sh
rust() { nix develop ./spikes/rust-stack/player -c "$@"; }
rust cargo fmt --manifest-path spikes/rust-stack/core/Cargo.toml
rust cargo fmt --manifest-path spikes/rust-stack/player/Cargo.toml
rust cargo test --manifest-path spikes/rust-stack/core/Cargo.toml world::tests
rust cargo test --manifest-path spikes/rust-stack/player/Cargo.toml --lib
rust cargo clippy --manifest-path spikes/rust-stack/player/Cargo.toml --lib -- -D warnings
if [[ ${GENERATE_REAL_SCREENS:-1} == 1 ]]; then
  nix-shell spikes/rust-stack/tools/generate-real-screens.py "$@"
fi
ROOT="$HOME/eggshell-remote/artifacts/full-rust-ab/scaling/${REAL_SCREENS_DIR:-real-screens-v2}"
SCHEMA="$HOME/eggshell-remote/artifacts/full-rust-ab/core/stride-4.7.2/schema.json"
for file in "$ROOT"/real-*.level.json; do
  name=${file##*/}; name=${name%.level.json}
  rust cargo run --manifest-path spikes/rust-stack/player/Cargo.toml -- --benchmark-host-check \
    "$file" src/level/collision_table.json "$SCHEMA" 120 real-screen
  rust cargo run --manifest-path spikes/rust-stack/player/Cargo.toml -- --benchmark-zoom-range \
    "$file" src/level/collision_table.json real-screen
  rust cargo run --manifest-path spikes/rust-stack/player/Cargo.toml -- --validate-real-screen-assets \
    "$file" src/level/collision_table.json "$HOME/.local/share/eggshell/packs/original-v3-final" \
    "$HOME/eggshell-remote/player-pack-files.sha256.json" \
    "$HOME/eggshell-remote/artifacts/full-rust-ab/player/presentation-stage/view-metrics.json" "$ROOT/asset-$name.json"
done
nix-shell spikes/rust-stack/tools/audit-real-screens.py
printf 'REAL_SCREEN_HOST_CHECKS_DONE faithful_real_level=false saves_disabled=true\n'
