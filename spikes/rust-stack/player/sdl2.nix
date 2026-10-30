{
  lib,
  stdenv,
  fetchurl,
  cmake,
  ninja,
  pkg-config,
  patchelf,
  wayland,
  wayland-protocols,
  wayland-scanner,
  libxkbcommon,
  libglvnd,
  libudev-zero,
}:
stdenv.mkDerivation {
  pname = "eggshell-spike-genuine-sdl2";
  version = "2.32.10";
  src = fetchurl {
    url = "https://www.libsdl.org/release/SDL2-2.32.10.tar.gz";
    hash = "sha256-X1mTxTDwhFNcZaaHnpsmrUQRabPiXXidgyhwQKnKUWU=";
  };
  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    wayland-scanner
    patchelf
  ];
  buildInputs = [
    wayland
    wayland-protocols
    libxkbcommon
    libglvnd
    libudev-zero
  ];
  cmakeFlags = [
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DSDL_SHARED=ON"
    "-DSDL_STATIC=OFF"
    "-DSDL_TEST=OFF"
    "-DSDL_TESTS=OFF"
    "-DSDL_X11=OFF"
    "-DSDL_WAYLAND=ON"
    "-DSDL_WAYLAND_SHARED=OFF"
    "-DSDL_WAYLAND_LIBDECOR=OFF"
    "-DSDL_OPENGL=OFF"
    "-DSDL_OPENGLES=ON"
    "-DSDL_VULKAN=OFF"
    "-DSDL_KMSDRM=OFF"
    "-DSDL_RPI=OFF"
    "-DSDL_DIRECTFB=OFF"
    "-DSDL_AUDIO=OFF"
    "-DSDL_ALSA=OFF"
    "-DSDL_PULSEAUDIO=OFF"
    "-DSDL_JACK=OFF"
    "-DSDL_PIPEWIRE=OFF"
    "-DSDL_IBUS=OFF"
    "-DSDL_FCITX=OFF"
    "-DSDL_HIDAPI=ON"
    "-DSDL_HIDAPI_LIBUSB=OFF"
  ];
  # EGL/GLES and udev are dlopened. Retain them in the Nix runtime closure.
  postFixup = ''
    patchelf --add-rpath ${
      lib.makeLibraryPath [
        libglvnd
        libudev-zero
      ]
    } "$out/lib/libSDL2-2.0.so.0.3200.10"
  '';
  strictDeps = true;
  meta.license = lib.licenses.zlib;
}
