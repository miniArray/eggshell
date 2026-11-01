#!/usr/bin/env nix-shell
#! nix-shell ../core/toolchain.nix -i bash
# aka only. Every Godot-reference parity check the core has: Stride milestone, then each fixture.
# Keeps going after a failure and prints one summary line per check.
set -uo pipefail
[[ $(hostname) == aka ]]
[[ "$NIX_CONFIG" == *'builders ='* ]]
failed=0
# Logs are per aka tree: lanes gate concurrently on one host.
check() {
  local name=$1
  shift
  if "$@" >"/tmp/$(basename "$PWD")-parity-$name.log" 2>&1; then
    printf 'PARITY_PASS %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'PARITY_FAIL %s\n' "$name"
    grep -a -E 'panicked|assert|expected|FAILED|ERROR|first|differ' "/tmp/$(basename "$PWD")-parity-$name.log" | head -12
  fi
}
check stride nix-shell spikes/rust-stack/oracle/milestone.sh
for fixture in bounce bounce.pad bounce.moves stride.eat lagoon collections actors_target stilts_target stilts_target.knock checkpoint_target posts_target posts_target.pound posts_target.duck blocks_target spans_target flats_target hards_target falls_target grows_target gates_target ledges_target stems_target flowers_target switches_target shells_target armored_target spears_target lifts_target snowflow_target fish_target melons_target thieves_target rollers_target shooters_target wings_target launchers_target sprouts_target jugglers_target bulks_target gusts_target hounds_target spores_target hangs_target eggblocks_target pillars_target balloons_target clears_target dice_target decor_target rejoin_target hopstems_target petals_target spitters_target elements_target spins_target sceneryledges_target thorns_target discs_target runners_target slimes_target spines_target ghosts_target snowtrees_target blanks_target softs_target helmets_target; do
  check "$fixture" nix-shell spikes/rust-stack/oracle/fixture.sh "$fixture"
done
printf 'PARITY_ALL_DONE failed=%s source=%s\n' "$failed" "$(git rev-parse HEAD)"
[[ "$failed" == 0 ]]
