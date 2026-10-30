# Resolve Rust/Godot from the baseline repository's locked nixpkgs, not NIX_PATH.
let
  lock = builtins.fromJSON (builtins.readFile ../../../flake.lock);
  source = builtins.fetchTree lock.nodes.nixpkgs.locked;
  pkgs = import source.outPath { };
in
pkgs.mkShell {
  packages = with pkgs; [
    cargo
    rustc
    rustfmt
    clippy
    python3
    godot_4
    git
    gdtoolkit_4
    ruff
    shellcheck
    nixfmt
  ];
}
