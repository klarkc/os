{ lib, pkgs, ... }:

let
  # Google IAP TCP forwarding source CIDR (IPv4); no VPN is used.
  iapSource = "35.235.240.0/20";
  xrdpModule = pkgs.callPackage ./pkgs/pipewire-module-xrdp.nix { };
  pipewireWithXrdp = pkgs.symlinkJoin {
    name = "pipewire-with-xrdp-${pkgs.pipewire.version}";
    paths = [ pkgs.pipewire xrdpModule ];
  };
  xrdpSession = pkgs.writeShellApplication {
    name = "wsklarkc-xrdp-session";
    runtimeInputs = with pkgs; [ coreutils gawk gnugrep pipewire pulseaudio procps systemd ];
    # ShellCheck cannot follow EXIT trap handlers; functions are invoked indirectly.
    excludeShellChecks = [ "SC2329" ];
    text = builtins.readFile ./scripts/xrdp-pipewire-session.sh;
  };
  xrdpPasswordBootstrap = pkgs.writeShellScriptBin "wsklarkc-xrdp-set-password" ''
    set -euo pipefail
    if [ "$(id -u)" != 0 ] || [ ! -t 0 ] || [ ! -t 1 ]; then
      echo "Use an interactive, authenticated IAP/OS Login SSH session: sudo wsklarkc-xrdp-set-password" >&2
      exit 1
    fi
    # Interactive tty input only. No hashes/passwords in Git, the store,
    # startup scripts, VM metadata, command arguments, or CI output.
    exec ${pkgs.shadow}/bin/passwd klarkc
  '';
in
{
  networking.hostName = "wsklarkc";
  time.timeZone = "America/Bahia";
  i18n.defaultLocale = "en_US.UTF-8";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "klarkc" ];

  # Defense in depth: accept administrative TCP only from Google IAP proxies.
  # Do NOT use allowedTCPPorts here: that would expose 22/3389 to all sources.
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    extraInputRules = ''
      ip saddr ${iapSource} tcp dport 3389 accept comment "IAP TCP RDP only"
      ip saddr ${iapSource} tcp dport 22 accept comment "IAP TCP OS Login SSH only"
    '';
  };

  services.xrdp = {
    enable = true;
    openFirewall = false;
    # XRDP authenticates remotely and creates its own Xorg session;
    # neither XFCE nor the local TTY greeter Lemurs is required.
    # One supervisor owns the PipeWire XRDP module for the entire XMonad
    # session, including RDP disconnect/reconnect. No XDG autostart required.
    defaultWindowManager = ''
      exec ${xrdpSession}/bin/wsklarkc-xrdp-session
    '';
  };
  # pam_systemd starts the real systemd --user manager and /run/user/UID.
  security.pam.services.xrdp-sesman = {
    allowNullPassword = lib.mkForce false;
    startSession = true;
  };
  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
    systemWide = false;
    # The running daemon searches this union for built-in + pinned XRDP
    # modules. The XRDP environment is deliberately NOT injected here.
    package = pipewireWithXrdp;
  };
  systemd.user.services.pipewire.environment.PIPEWIRE_MODULE_DIR =
    "${pipewireWithXrdp}/lib/pipewire-0.3";

  services.xserver = {
    enable = true;
    xkb.layout = "br";
    windowManager.xmonad = {
      enable = true;
      # HOME xmonad.hs imports xmonad-contrib: preserve its Haskell deps.
      enableContribAndExtras = true;
    };
  };

  users.users.klarkc = {
    isNormalUser = true;
    home = "/home/klarkc";
    createHome = true;
    shell = pkgs.bashInteractive;
    extraGroups = [ "wheel" ];
    # Set an interactive password only AFTER OS Login administration through IAP.
    initialHashedPassword = "!";
  };

  security.sudo.wheelNeedsPassword = true;
  services.openssh = {
    enable = true;
    openFirewall = false; # Explicit CIDR-bound nftables exception above.
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  environment.systemPackages = with pkgs; [
    git curl wget openssh tmux direnv bashInteractive
    xterm alacritty
    xorg.xauth xorg.xsetroot xorg.xmodmap
    xclip dbus dunst
    nix-output-monitor
    gnumake gcc
    google-cloud-sdk
    xrdpPasswordBootstrap xrdpModule xrdpSession
  ];

  # GCE image module provides Google OS Login and the GCE guest agent.
  # Neither credentials nor a Tailscale/WireGuard identity is embedded.
  system.stateVersion = "26.05";
}
