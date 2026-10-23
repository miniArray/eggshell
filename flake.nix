{
  description = "Eggshell Godot development and Linux runtime";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: import ./nix/outputs.nix { inherit self nixpkgs; };
}
