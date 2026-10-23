{ pkgs, arm64 }:
# Official, mostly static release template; no editor, GTK, or audio closure on target.
pkgs.runCommand "eggshell-godot-arm64-${pkgs.godot_4.version}"
  {
    nativeBuildInputs = [ pkgs.patchelf ];
  }
  ''
    mkdir -p "$out/lib"
    cp ${pkgs.godot_4-export-templates-bin}/share/godot/export_templates/${
      builtins.replaceStrings [ "-" ] [ "." ] pkgs.godot_4.version
    }/linux_release.arm64 "$out/godot"
    chmod u+w "$out/godot"
    for library in ld-linux-aarch64.so.1 libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1; do
      cp -L ${arm64.glibc}/lib/"$library" "$out/lib/$library"
    done
    patchelf --set-interpreter /tmp/eggshell/runtime/lib/ld-linux-aarch64.so.1 \
      --set-rpath '$ORIGIN/lib' "$out/godot"
  ''
