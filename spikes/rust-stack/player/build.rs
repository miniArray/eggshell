use std::{env, path::PathBuf, process::Command};
fn main() {
    println!("cargo:rerun-if-changed=native/presentation.c");
    println!("cargo:rerun-if-env-changed=WAYLAND_PROTOCOLS_DATADIR");
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let protocols = PathBuf::from(
        env::var_os("WAYLAND_PROTOCOLS_DATADIR")
            .expect("use the spike-local pinned Nix shell (Wayland protocol XML required)"),
    );
    let xml = protocols.join("stable/presentation-time/presentation-time.xml");
    for (mode, file) in [
        ("client-header", "presentation-time-client-protocol.h"),
        ("private-code", "presentation-time-protocol.c"),
    ] {
        let status = Command::new("wayland-scanner")
            .arg(mode)
            .arg(&xml)
            .arg(out.join(file))
            .status()
            .expect("native wayland-scanner");
        assert!(status.success(), "protocol generation failed");
    }
    let sdl = pkg_config::Config::new()
        .cargo_metadata(false)
        .probe("sdl2")
        .expect("system genuine SDL2 headers");
    let wl = pkg_config::Config::new()
        .cargo_metadata(false)
        .probe("wayland-client")
        .expect("system Wayland headers");
    // Nix's fortified libc headers require optimized C even in Rust debug checks.
    cc::Build::new()
        .opt_level(2)
        .include(&out)
        .includes(sdl.include_paths)
        .includes(wl.include_paths)
        .file("native/presentation.c")
        .file(out.join("presentation-time-protocol.c"))
        .warnings(true)
        .warnings_into_errors(true)
        .compile("eggshell_presentation");
    for path in wl.link_paths {
        println!("cargo:rustc-link-search=native={}", path.display());
    }
    for lib in wl.libs {
        println!("cargo:rustc-link-lib={lib}");
    }
}
