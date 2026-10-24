{
  buildPkgs,
  runtimePkgs,
  source,
}:
# Eggshell for Linux: one game pack exported on the build machine and the same
# Godot version from nixpkgs as the runtime. Devices download both; nothing builds there.
let
  exporter =
    assert buildPkgs.godot_4.version == "4.7.2-stable";
    buildPkgs.godot_4;
  runtime =
    assert runtimePkgs.godot_4.version == exporter.version;
    runtimePkgs.godot_4;
  lib = buildPkgs.lib;
  gameSource = lib.fileset.toSource {
    root = source;
    fileset = lib.fileset.unions [
      (source + /project.godot)
      (source + /export_presets.cfg)
      (source + /src)
      (source + /packs/pantry)
      (source + /tests/fixtures)
    ];
  };
  pack =
    buildPkgs.runCommand "eggshell-pack"
      {
        nativeBuildInputs = [ exporter ];
      }
      ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/config"
        export XDG_DATA_HOME="$HOME/data"
        export XDG_CACHE_HOME="$HOME/cache"
        mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
        cp -r ${gameSource} source
        chmod -R u+w source
        cd source
        godot --headless --path . --editor --import --quit > import.log 2>&1 || true
        cat import.log
        if grep -E 'SCRIPT ERROR:|^ERROR:' import.log; then exit 1; fi
        mkdir -p "$out"
        godot --headless --path . --export-pack "Linux ARM64" "$out/eggshell.pck" > export.log 2>&1
        cat export.log
        if grep -E 'SCRIPT ERROR:|^ERROR:' export.log; then exit 1; fi
        test -s "$out/eggshell.pck"
      '';
in
buildPkgs.runCommand "eggshell"
  {
    passthru = { inherit pack runtime; };
    meta = {
      description = "Eggshell level player with the Pantry graphics pack";
      mainProgram = "eggshell";
    };
  }
  ''
    mkdir -p "$out/bin" "$out/share/eggshell"
    ln -s ${pack}/eggshell.pck "$out/share/eggshell/eggshell.pck"
    cat > "$out/bin/eggshell" <<'LAUNCHER'
    #!${runtimePkgs.runtimeShell}
    # Usage: eggshell [godot options] -- --level-code=PATH [--save-dir=PATH] [game options]
    exec ${runtime}/bin/godot --main-pack ${pack}/eggshell.pck ${
      lib.optionalString (
        runtimePkgs.stdenv.hostPlatform.system == "aarch64-linux"
      ) "--rendering-method gl_compatibility --rendering-driver opengl3_es"
    } "$@"
    LAUNCHER
    chmod +x "$out/bin/eggshell"
  ''
