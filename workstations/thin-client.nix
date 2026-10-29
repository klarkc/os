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
    # Connection/pairing UI runs directly on the trusted local console.
    # The X11 server is started only when an RDP session is available.
    exec ${pkgs.bash}/bin/bash ${./scripts/thin-client.sh} "$@"
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

  # Rootless Xorg is still needed by xfreerdp. The Dell does NOT need a
  # display manager, window manager, terminal emulator or desktop session.
  # Start Xorg with startx only after a valid Google IAP tunnel is ready.
  # NixOS automatically enables the generic graphical-desktop profile
  # whenever xserver.enable = true. That profile pulls in speech synthesis
  # (including ~676MB of mbrola voices), PipeWire, CJK fonts, XDG tools,
  # desktop icons, pinentry and additional graphical libraries. An
  # on-demand Xorg session running only FreeRDP needs none of these.
  services.graphical-desktop.enable = lib.mkForce false;
  services.speechd.enable = lib.mkForce false;
  services.pipewire.enable = lib.mkForce false;
  fonts.enableDefaultPackages = lib.mkForce false;
  # FreeRDP 2D and the modesetting driver should not need Mesa/LLVM DRI.
  # QEMU tests the actual Xorg startx path before any ISO is published.
  hardware.graphics.enable = lib.mkForce false;
  services.xserver.enable = true;
  services.xserver.xkb.layout = "br";
  services.xserver.displayManager.startx.enable = true;
  services.xserver.windowManager.openbox.enable = lib.mkForce false;
  services.xserver.displayManager.lightdm.enable = lib.mkForce false;

  # The local kiosk starts from autologin on tty1. Keep tty2/other consoles
  # for recovery. startx runs under 'nixos', never as root.
  services.getty.autologinUser = "nixos";
  environment.loginShellInit = ''
    if [ "$(id -un)" = "nixos" ] && [ "$(tty)" = "/dev/tty1" ] && [ -z "$DISPLAY" ]; then
      exec ${thinClient}/bin/lpklarkc
    fi
  '';

  environment.systemPackages = with pkgs; [
    stateTool iapTool thinClient freerdp networkmanager
    google-cloud-sdk sqlite netcat-openbsd openssh
    # NixOS' system-path post-build expects share/icons for icon cache
    # generation. Keep only the tiny theme index, not the desktop stack.
    hicolor-icon-theme
  ];
  console.keyMap = "br-abnt2";
  time.timeZone = "America/Bahia";
  system.stateVersion = "26.05";
}
