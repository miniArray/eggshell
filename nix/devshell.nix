{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    godot_4
    xorg-server # Xvfb for GPU readback tests without a desktop.
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
