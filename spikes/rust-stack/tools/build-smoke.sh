#!/usr/bin/env nix-shell
#! nix-shell -i bash -p bash coreutils git nix python3 patchelf binutils gnutar gzip shellcheck
set -euo pipefail
export NIX_CONFIG='builders ='
test "$(hostname)" = aka
: "${EXPECTED_SOURCE_SHA:?must pin a full tested source SHA}"
test "$(git rev-parse HEAD)" = "$EXPECTED_SOURCE_SHA"
test -z "$(git status --porcelain --untracked-files=no)"
if [[ -n "${EXPECTED_CORE_TREE:-}" ]]; then
  test "$(git rev-parse HEAD:spikes/rust-stack/core)" = "$EXPECTED_CORE_TREE"
fi
git ls-files --error-unmatch tests/fixtures/bounce.level.json tests/fixtures/lagoon.level.json \
  spikes/rust-stack/core/tests/fixtures/collections.level.json
git diff --exit-code 297ada9a022d0ddc297dd2d4091c5dccfab4531e -- \
  tests/fixtures/bounce.level.json tests/fixtures/lagoon.level.json
nix config show | grep '^builders ='
ROOT=$PWD
OUT="$HOME/eggshell-remote/artifacts/full-rust-ab/player/$EXPECTED_SOURCE_SHA"
test ! -e "$OUT"
cd spikes/rust-stack/player
nix build --no-link --print-out-paths -L .#arm64 > "$HOME/eggshell-remote/player-built-path"
PACKAGE=$(cat "$HOME/eggshell-remote/player-built-path")
cd "$ROOT"
if [[ "${PLAYER_PLAYTEST_BUNDLE:-}" == 1 ]]; then
  # Level list index of this source (host build of the same tree): which corpus levels play.
  if [[ -n "${PLAYER_EXTRA_LEVELS:-}" ]]; then
    # Private extra levels (never Git) join the corpus in the list: a folder of links.
    PLAYER_LEVELS_DIR="$HOME/eggshell-remote/levels-with-extra"
    rm -rf "$PLAYER_LEVELS_DIR"
    mkdir -p "$PLAYER_LEVELS_DIR"
    ln -s "$HOME/.local/share/eggshell-run/corpus/levels/"*.json "$PLAYER_EXTRA_LEVELS/"*.json "$PLAYER_LEVELS_DIR/"
    export PLAYER_LEVELS_DIR
  fi
  LEVEL_INDEX="$HOME/eggshell-remote/level-index-$EXPECTED_SOURCE_SHA.json"
  bash spikes/rust-stack/tools/level-index.sh "$LEVEL_INDEX"
  export LEVEL_INDEX
fi
# Assets enter only this private post-build bundle, never a Nix source or derivation.
python3 spikes/rust-stack/tools/bundle-player.py "$PACKAGE" "$OUT"
nix --version > "$OUT/nix-version.txt"
nix develop ./spikes/rust-stack/player -c rustc -Vv > "$OUT/rustc-version.txt"
readelf -h "$PACKAGE/bin/eggshell-spike-player" > "$OUT/elf-header.txt"
readelf -d "$PACKAGE/bin/eggshell-spike-player" > "$OUT/elf-dynamic.txt"
tar -tzf "$OUT/smoke-arm64.tar.gz" > "$OUT/archive-content.txt"
git ls-files spikes/rust-stack/player spikes/rust-stack/core spikes/rust-stack/tools | xargs sha256sum > "$OUT/source-files.sha256"
printf 'RUST_SMOKE_BUILD_DONE source=%s artifact=%s\n' "$EXPECTED_SOURCE_SHA" "$OUT"
