{ lib, pkgs, ... }:

let
  stateTool = pkgs.writeShellScriptBin "thin-client-state" ''
    exec ${pkgs.bash}/bin/bash ${./scripts/ventoy-state.sh} "$@"
  '';
  thinClient = pkgs.writeShellScriptBin "thin-client" ''
    exec ${pkgs.xterm}/bin/xterm \
      -T "Remote workstation - connection" \
      -fa "DejaVu Sans Mono" -fs 12 \
      -bg "#101820" -fg "#eeeeee" \
      -geometry 100x28 \
      -e ${pkgs.bash}/bin/bash ${./scripts/thin-client.sh}
  '';
in
{
  networking.hostName = "thin-client";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  services.openssh.enable = lib.mkForce false;
  services.tailscale.enable = true;

  # Restore USB state before NetworkManager and Tailscale start.
  systemd.services.thin-client-ventoy-state = {
    description = "Restore trusted Ventoy USB connection state";
    wantedBy = [ "multi-user.target" ];
    before = [ "NetworkManager.service" "tailscaled.service" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.util-linux pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.findutils ];
    script = "${stateTool}/bin/thin-client-state restore";
  };
  systemd.services.NetworkManager.requires = [ "thin-client-ventoy-state.service" ];
  systemd.services.tailscaled.requires = [ "thin-client-ventoy-state.service" ];

  # Periodic best-effort copies also capture newly configured Wi-Fi and
  # the rotating Tailscale state before an unexpected reboot.
  systemd.services.thin-client-save-state = {
    description = "Save thin-client runtime state to Ventoy";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.util-linux pkgs.coreutils pkgs.findutils ];
    script = "${stateTool}/bin/thin-client-state save || true";
  };
  systemd.timers.thin-client-save-state = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "45s"; OnUnitActiveSec = "1min"; };
  };
  systemd.services.thin-client-save-on-shutdown = {
    description = "Save thin-client state on shutdown";
    wantedBy = [ "multi-user.target" ];
    after = [ "thin-client-ventoy-state.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = "${pkgs.coreutils}/bin/true"; ExecStop = "${stateTool}/bin/thin-client-state save"; };
    path = [ pkgs.util-linux pkgs.coreutils pkgs.findutils ];
  };

  services.xserver.enable = true;
  services.xserver.xkb.layout = "br";
  services.xserver.windowManager.openbox.enable = true;
  services.xserver.displayManager.lightdm = {
    enable = true;
    greeter.enable = false;
  };
  services.displayManager = {
    autoLogin = { enable = true; user = "nixos"; };
    defaultSession = "none+openbox";
  };
  services.xserver.displayManager.sessionCommands = ''
    ${thinClient}/bin/thin-client &
  '';

  environment.systemPackages = with pkgs; [
    stateTool thinClient freerdp networkmanager tailscale
    jq xterm xorg.xsetroot openssh
  ];
  fonts.packages = [ pkgs.dejavu_fonts ];
  console.keyMap = "br-abnt2";
  time.timeZone = "America/Bahia";
  system.stateVersion = "26.05";
}
