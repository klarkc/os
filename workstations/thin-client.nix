{ lib, pkgs, ... }:

let
  stateTool = pkgs.writeShellScriptBin "lpklarkc-state" ''
    export PATH=${lib.makeBinPath [ pkgs.util-linux pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.findutils pkgs.sqlite pkgs.systemd pkgs.lvm2 pkgs.networkmanager ]}:$PATH
    exec ${pkgs.bash}/bin/bash ${./scripts/ventoy-state.sh} "$@"
  '';
  iapTool = pkgs.writeShellScriptBin "lpklarkc-iap" ''
    export PATH=${lib.makeBinPath [ pkgs.google-cloud-sdk pkgs.coreutils pkgs.sudo ]}:$PATH
    exec ${pkgs.bash}/bin/bash ${./scripts/gce-iap.sh} "$@"
  '';
  thinClient = pkgs.writeShellScriptBin "lpklarkc" ''
    # CLI diagnostic mode without X11; used by deterministic CI regressions.
    if [ "$1" = "--check-network" ]; then
      exec ${pkgs.bash}/bin/bash ${./scripts/thin-client.sh} --check-network
    fi
    exec ${pkgs.xterm}/bin/xterm \
      -fullscreen -b 18 \
      -T "lpklarkc" \
      -fa "DejaVu Sans Mono" -fs 15 \
      -bg "#101820" -fg "#ecf2fa" -cr "#61ddc2" \
      -e ${pkgs.bash}/bin/bash ${./scripts/thin-client.sh}
  '';
in
{
  networking.hostName = "lpklarkc";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  services.openssh.enable = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;

  # Quiet boot, kiosk-like interface, diagnostic console still available.
  boot.consoleLogLevel = lib.mkDefault 3;
  boot.initrd.verbose = lib.mkDefault false;
  boot.kernelParams = [
    "quiet" "loglevel=3" "systemd.show_status=0"
    "udev.log_level=3" "rd.udev.log_level=3"
  ];

  # The kiosk can only save state or recover a validated USB. The ensure
  # helper restores a narrow whitelist after a late mount; arbitrary shell
  # execution, internal disks and other privileged operations are denied.
  security.sudo.extraRules = [{
    users = [ "nixos" ];
    commands = [
      { command = "/run/current-system/sw/bin/lpklarkc-state save"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/lpklarkc-state ensure"; options = [ "NOPASSWD" ]; }
    ];
  }];

  # Restore USB credentials before NetworkManager and graphical autologin.
  # The USB and Wi-Fi profiles are the only persistence; never write the HDD.
  systemd.services.lpklarkc-ventoy-state = {
    description = "Restore trusted Ventoy USB Wi-Fi and Google CLI state";
    wantedBy = [ "multi-user.target" ];
    before = [ "NetworkManager.service" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.util-linux pkgs.coreutils pkgs.gnugrep pkgs.gawk pkgs.findutils pkgs.sqlite pkgs.systemd pkgs.lvm2 ];
    script = "${stateTool}/bin/lpklarkc-state restore";
  };
  systemd.services.NetworkManager.requires = [ "lpklarkc-ventoy-state.service" ];

  # Periodic sqlite online backup captures Google refresh-token updates.
  systemd.services.lpklarkc-save-state = {
    description = "Save Wi-Fi and Google CLI credentials to trusted Ventoy USB";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.util-linux pkgs.coreutils pkgs.findutils pkgs.sqlite ];
    script = "${stateTool}/bin/lpklarkc-state save || true";
  };
  systemd.timers.lpklarkc-save-state = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "45s"; OnUnitActiveSec = "1min"; };
  };
  systemd.services.lpklarkc-save-on-shutdown = {
    description = "Save thin-client state on shutdown";
    wantedBy = [ "multi-user.target" ];
    after = [ "lpklarkc-ventoy-state.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
      ExecStop = "${stateTool}/bin/lpklarkc-state save";
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
    ${thinClient}/bin/lpklarkc &
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
