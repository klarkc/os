{ lib, pkgs, ... }:

let
  stateTool = pkgs.writeShellScriptBin "solo-client-state" ''
    export PATH=${lib.makeBinPath [ pkgs.util-linux pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.findutils pkgs.wireguard-tools ]}:$PATH
    exec ${pkgs.bash}/bin/bash ${./scripts/ventoy-state.sh} "$@"
  '';
  gceTool = pkgs.writeShellScriptBin "solo-gce-endpoint" ''
    export PATH=${lib.makeBinPath [ pkgs.google-cloud-sdk pkgs.curl pkgs.jq pkgs.coreutils pkgs.sudo ]}:$PATH
    exec ${pkgs.bash}/bin/bash ${./scripts/gce-endpoint.sh} "$@"
  '';
  wgTool = pkgs.writeShellScriptBin "solo-client-wg" ''
    export PATH=${lib.makeBinPath [ pkgs.iproute2 pkgs.wireguard-tools pkgs.coreutils pkgs.util-linux pkgs.kmod ]}:$PATH
    exec ${pkgs.bash}/bin/bash ${./scripts/client-wg.sh} "$@"
  '';
  thinClient = pkgs.writeShellScriptBin "solo-thin-client" ''
    export SOLO_STATE_TOOL=/run/current-system/sw/bin/solo-client-state
    export SOLO_GCE_TOOL=/run/current-system/sw/bin/solo-gce-endpoint
    export SOLO_WG_TOOL=/run/current-system/sw/bin/solo-client-wg
    exec ${pkgs.xterm}/bin/xterm \
      -T "Solo Workstation - connection" \
      -fa "DejaVu Sans Mono" -fs 12 \
      -bg "#101820" -fg "#eeeeee" \
      -geometry 100x28 \
      -e ${pkgs.bash}/bin/bash ${./scripts/thin-client.sh}
  '';
in
{
  networking.hostName = "solo-thin-client";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  services.openssh.enable = lib.mkForce false;
  # Tailscale requires managed coordination and is replaced with a WireGuard
  # route to the GCE endpoint discovered through the owner's Google OAuth.
  services.tailscale.enable = lib.mkForce false;

  # Only these fixed helpers are allowed without sudo password. Google OAuth
  # itself always runs as the unprivileged nixos user, NEVER as root.
  security.sudo.extraRules = [{
    users = [ "nixos" ];
    commands = [
      { command = "/run/current-system/sw/bin/solo-client-state"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/solo-client-wg"; options = [ "NOPASSWD" ]; }
    ];
  }];

  # Restore USB state before NetworkManager starts or graphical autologin.
  # No disk format, internal HDD mount, swap creation or copytoram.
  systemd.services.solo-ventoy-state = {
    description = "Restore trusted Ventoy USB credentials and connection state";
    wantedBy = [ "multi-user.target" ];
    before = [ "NetworkManager.service" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.util-linux pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.findutils pkgs.wireguard-tools ];
    script = "${stateTool}/bin/solo-client-state restore";
  };
  systemd.services.NetworkManager.requires = [ "solo-ventoy-state.service" ];

  # Best-effort copies capture any newly saved Wi-Fi or OAuth state.
  systemd.services.solo-save-state = {
    description = "Save thin-client runtime state to Ventoy";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.util-linux pkgs.coreutils pkgs.findutils ];
    script = "${stateTool}/bin/solo-client-state save || true";
  };
  systemd.timers.solo-save-state = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "45s"; OnUnitActiveSec = "1min"; };
  };
  systemd.services.solo-save-on-shutdown = {
    description = "Save thin-client state on shutdown";
    wantedBy = [ "multi-user.target" ];
    after = [ "solo-ventoy-state.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; ExecStart = "${pkgs.coreutils}/bin/true"; ExecStop = "${stateTool}/bin/solo-client-state save"; };
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
    ${thinClient}/bin/solo-thin-client &
  '';

  environment.systemPackages = with pkgs; [
    stateTool gceTool wgTool thinClient freerdp networkmanager
    google-cloud-sdk curl jq iproute2 wireguard-tools
    xterm xorg.xsetroot openssh
  ];
  fonts.packages = [ pkgs.dejavu_fonts ];
  console.keyMap = "br-abnt2";
  time.timeZone = "America/Bahia";
  system.stateVersion = "26.05";
}
