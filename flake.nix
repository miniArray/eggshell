{
  description = "Eggshell: a Rust platform-level player for Linux handhelds";

  # The game builds from spikes/rust-stack/player (its own flake: `nix build
  # ./spikes/rust-stack/player#arm64`). This flake pins the nixpkgs that the core
  # tool shell (spikes/rust-stack/core/toolchain.nix) reads from flake.lock.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in
    {
      devShells.x86_64-linux.default = import ./spikes/rust-stack/core/toolchain.nix;
      formatter.x86_64-linux = pkgs.nixfmt;
    };
}
