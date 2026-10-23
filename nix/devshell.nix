{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    godot_4
    python3
    nodejs
    git
    openssh
    patchelf
    binutils
    shellcheck
    gdtoolkit_4
    ruff
    nixfmt
  ];
}
