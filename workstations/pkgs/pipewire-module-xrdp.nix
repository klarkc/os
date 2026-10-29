{ stdenv, lib, fetchFromGitHub, autoreconfHook, pkg-config, autoconf-archive, pipewire }:

# Same pinned nixpkgs PipeWire is used for headers, libraries and the
# running server. Upstream does not ship a prebuilt NixOS package.
stdenv.mkDerivation {
  pname = "pipewire-module-xrdp";
  version = "0.2-2026-03-24";

  src = fetchFromGitHub {
    owner = "neutrinolabs";
    repo = "pipewire-module-xrdp";
    rev = "a6e268b17093f8aab4e0fed9dcb23eaf87f7101c";
    hash = "sha256-t3xtbvPVRnkyJOJka6sYoyk1bw/ddd9+xfs+eMh+95Y=";
  };

  nativeBuildInputs = [ autoreconfHook pkg-config autoconf-archive ];
  buildInputs = [ pipewire ];

  # XMonad has no XDG autostart runner. A single, supervised session
  # wrapper starts the module instead; prevent upstream desktop autostart
  # from accidentally loading a second instance.
  configureFlags = [
    "--with-module-dir=${placeholder "out"}/lib/pipewire-0.3"
    "--with-xdgautostart-dir=${placeholder "out"}/share/xrdp-disabled-autostart"
    "--disable-alt-pw-cli"
  ];

  postInstall = ''
    test -s "$out/lib/pipewire-0.3/libpipewire-module-xrdp.so"
  '';

  meta = with lib; {
    description = "PipeWire XRDP sink and source module for RDP sound and microphone";
    homepage = "https://github.com/neutrinolabs/pipewire-module-xrdp";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
