{ lib, pkgs, ... }:

let
  stateTool = pkgs.writeShellScriptBin "solo-client-state" ''
    export PATH=${lib.makeBinPath [ pkgs.util-linux pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.findutils pkgs.sqlite ]}:$PATH
    exec ${pkgs.bash}/bin/bash ${./scripts/ventoy-state.sh} "$@"
  '';
  iapTool = pkgs.writeShellScriptBin "solo-gce-iap" ''
    export PATH=${lib.makeBinPath [ pkgs.google-cloud-sdk pkgs.coreutils pkgs.sudo ]}:$PATH
    exec ${pkgs.bash}/bin/bash ${./scripts/gce-iap.sh} "$@"
  '';
  thinClient = pkgs.writeShellScriptBin "solo-thin-client" ''
    exec ${pkgs.xterm}/bin/xterm \
      -T "Solo Workstation - Google IAP / RDP" \
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
  services.tailscale.enable = lib.mkForce false;

  # Only saving Ventoy state requires privilege from the GUI account.
  # Restore is reserved for the boot-time systemd service; there is no
  # passwordless access to arbitrary network, disk or WireGuard helpers.
  security.sudo.extraRules = [{
    users = [ "nixos" ];
    commands = [
      { command = "/run/current-system/sw/bin/solo-client-state save"; options = [ "NOPASSWD" ]; }
    ];
  }];

  # Restore USB credentials before NetworkManager and graphical autologin.
  # The USB and Wi-Fi profiles are the only persistence; never write the HDD.
  systemd.services.solo-ventoy-state = {
    description = "Restore trusted Ventoy USB Wi-Fi and Google CLI state";
    wantedBy = [ "multi-user.target" ];
    before = [ "NetworkManager.service" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.util-linux pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.findutils pkgs.sqlite ];
    script = "${stateTool}/bin/solo-client-state restore";
  };
  systemd.services.NetworkManager.requires = [ "solo-ventoy-state.service" ];

  # Periodic sqlite online backup captures Google refresh-token updates.
  systemd.services.solo-save-state = {
    description = "Save Wi-Fi and Google CLI credentials to trusted Ventoy USB";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.util-linux pkgs.coreutils pkgs.findutils pkgs.sqlite ];
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
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = "${stateTool}/bin/solo-client-state save";
    };
    path = [ pkgs.util-linux pkgs.coreutils pkgs.findutils pkgs.sqlite ];
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
    stateTool iapTool thinClient freerdp networkmanager
    google-cloud-sdk sqlite netcat-openbsd
    xterm xorg.xsetroot openssh
  ];
  fonts.packages = [ pkgs.dejavu_fonts ];
  console.keyMap = "br-abnt2";
  time.timeZone = "America/Bahia";
  system.stateVersion = "26.05";
}
