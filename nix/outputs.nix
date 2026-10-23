{ self, nixpkgs }:
let
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  eachSystem = nixpkgs.lib.genAttrs systems;
in
{
  packages = eachSystem (
    system:
    let
      pkgs = import nixpkgs { inherit system; };
    in
    {
      default = pkgs.godot_4;
      godot = pkgs.godot_4;
      templates = pkgs.godot_4-export-templates-bin;
      runtime-arm64 = import ./runtime-arm64.nix {
        inherit pkgs;
        arm64 = import nixpkgs { system = "aarch64-linux"; };
      };
    }
  );
  devShells = eachSystem (
    system:
    let
      pkgs = import nixpkgs { inherit system; };
    in
    {
      default = import ./devshell.nix { inherit pkgs; };
    }
  );
}
