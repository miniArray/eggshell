{
  description = "Throwaway standalone Rust-owned Eggshell player; no private assets";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
    }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ rust-overlay.overlays.default ];
      };
      cross = import nixpkgs {
        system = "x86_64-linux";
        crossSystem.config = "aarch64-unknown-linux-gnu";
        overlays = [ rust-overlay.overlays.default ];
      };
      toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
      # Deliberately genuine SDL2, not the SDL3-backed sdl2-compat alias.
      sdl = p: p.callPackage ./sdl2.nix { };
      build =
        p:
        (p.makeRustPlatform {
          cargo = toolchain;
          rustc = toolchain;
        }).buildRustPackage
          {
            pname = "eggshell-spike-player";
            version = "0.1.0";
            src = pkgs.lib.fileset.toSource {
              # Admission guards include these tracked public fixtures relative
              # to the repository. Preserve that layout; never add private data.
              root = ../../..;
              fileset = pkgs.lib.fileset.unions [
                ./Cargo.toml
                ./Cargo.lock
                ./src
                ./tests/fixtures/lighting.level.json
                ./native
                ./build.rs
                ../core/Cargo.toml
                ../core/src
                ../core/tests/fixtures/collections.level.json
                ../core/tests/fixtures/actors_target.level.json
                ../core/tests/fixtures/stilts_target.level.json
                ../core/tests/fixtures/checkpoint_target.level.json
                ../core/tests/fixtures/posts_target.level.json
                ../../../data/collision_table.json
                ../../../tests/fixtures/bounce.level.json
                ../../../tests/fixtures/lagoon.level.json
              ];
            };
            sourceRoot = "source/spikes/rust-stack/player";
            cargoLock.lockFile = ./Cargo.lock;
            nativeBuildInputs = [
              pkgs.pkg-config
              pkgs.wayland-scanner
            ];
            buildInputs = [
              (sdl p)
              p.wayland
            ];
            WAYLAND_PROTOCOLS_DATADIR = "${pkgs.wayland-protocols}/share/wayland-protocols";
            doCheck = p.stdenv.buildPlatform.canExecute p.stdenv.hostPlatform;
            strictDeps = true;
          };
    in
    {
      packages.x86_64-linux = {
        default = build pkgs;
        arm64 = build cross;
        sdl2-arm64 = sdl cross;
      };
      devShells.x86_64-linux.default = pkgs.mkShell {
        WAYLAND_PROTOCOLS_DATADIR = "${pkgs.wayland-protocols}/share/wayland-protocols";
        packages = [
          toolchain
          pkgs.pkg-config
          pkgs.wayland
          pkgs.wayland-scanner
          (sdl pkgs)
          pkgs.patchelf
          pkgs.binutils
          pkgs.python3
          pkgs.shellcheck
          pkgs.nixfmt
        ];
      };
    };
}
