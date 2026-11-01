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
  xorg,
  libglvnd,
  libudev-zero,
  libpulseaudio,
  alsa-lib,
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
    xorg.libX11
    xorg.libXext
    libglvnd
    libudev-zero
    libpulseaudio
    alsa-lib
  ];
  cmakeFlags = [
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DSDL_SHARED=ON"
    "-DSDL_STATIC=OFF"
    "-DSDL_TEST=OFF"
    "-DSDL_TESTS=OFF"
    "-DSDL_X11=ON"
    "-DSDL_X11_SHARED=OFF"
    "-DSDL_X11_XCURSOR=OFF"
    "-DSDL_X11_XINPUT=OFF"
    "-DSDL_X11_XFIXES=OFF"
    "-DSDL_X11_XRANDR=OFF"
    "-DSDL_X11_XSCRNSAVER=OFF"
    "-DSDL_X11_XSHAPE=OFF"
    "-DSDL_X11_XDBE=OFF"
    "-DSDL_WAYLAND=ON"
    "-DSDL_WAYLAND_SHARED=OFF"
    "-DSDL_WAYLAND_LIBDECOR=OFF"
    "-DSDL_OPENGL=OFF"
    "-DSDL_OPENGLES=ON"
    "-DSDL_VULKAN=OFF"
    "-DSDL_KMSDRM=OFF"
    "-DSDL_RPI=OFF"
    "-DSDL_DIRECTFB=OFF"
    # Playback through the Pro's sound server (PulseAudio protocol), else ALSA.
    # Both are dlopened; the bundle carries the libraries.
    "-DSDL_AUDIO=ON"
    "-DSDL_PULSEAUDIO=ON"
    "-DSDL_PULSEAUDIO_SHARED=ON"
    "-DSDL_ALSA=ON"
    "-DSDL_ALSA_SHARED=ON"
    "-DSDL_SNDIO=OFF"
    "-DSDL_OSS=OFF"
    "-DSDL_JACK=OFF"
    "-DSDL_PIPEWIRE=OFF"
    "-DSDL_IBUS=OFF"
    "-DSDL_FCITX=OFF"
    "-DSDL_HIDAPI=ON"
    "-DSDL_HIDAPI_LIBUSB=OFF"
  ];
  # EGL/GLES, udev and the audio libraries are dlopened. Retain them in the Nix runtime closure.
  postFixup = ''
    patchelf --add-rpath ${
      lib.makeLibraryPath [
        libglvnd
        libudev-zero
        libpulseaudio
        alsa-lib
      ]
    } "$out/lib/libSDL2-2.0.so.0.3200.10"
  '';
  strictDeps = true;
  meta.license = lib.licenses.zlib;
}
