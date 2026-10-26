{ lib, pkgs, ... }:

let
  # This script contains no site credentials. Wi-Fi and tailnet sign-in happen
  # interactively at runtime; no private material enters the public ISO.
  thinClient = pkgs.writeShellScriptBin "solo-thin-client" ''
    exec ${pkgs.xterm}/bin/xterm \
      -T "Workstation remota | Conexao" \
      -fa "DejaVu Sans Mono" -fs 12 \
      -bg "#101820" -fg "#eeeeee" \
      -geometry 108x31 \
      -e ${pkgs.bash}/bin/bash ${./scripts/thin-client.sh}
  '';
in
{
  networking.hostName = "solo-thin-client";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # The ISO is intentionally disposable: it never mounts or writes the
  # borrowed laptop's internal drive. Ventoy's data partition is read-only
  # unless the user explicitly configures private persistence later.
  services.openssh.enable = lib.mkForce false;
  services.tailscale.enable = true;

  services.xserver.enable = true;
  services.xserver.xkb.layout = "br";
  services.xserver.windowManager.openbox.enable = true;
  services.xserver.displayManager.lightdm = {
    enable = true;
    greeter.enable = false;
  };
  services.displayManager = {
    autoLogin = {
      enable = true;
      user = "nixos";
    };
    defaultSession = "none+openbox";
  };

  # A minimal X11 session is necessary to host FreeRDP, not a local desktop.
  # The Xterm below is a recovery surface only until a remote login appears.
  services.xserver.displayManager.sessionCommands = ''
    ${thinClient}/bin/solo-thin-client &
  '';

  environment.systemPackages = with pkgs; [
    thinClient
    freerdp
    networkmanager
    tailscale
    jq
    xterm
    xorg.xsetroot
    openssh
  ];

  fonts.packages = [ pkgs.dejavu_fonts ];
  console.keyMap = "br-abnt2";
  time.timeZone = "America/Bahia";

  isoImage.isoName = "solo-thin-client-x86_64.iso";

  # Do not copy the full ISO into RAM: the client notebook has only 4 GiB.
  # The image remains backed by the Ventoy USB while running.
  system.stateVersion = "26.05";
}
