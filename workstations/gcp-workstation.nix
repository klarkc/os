{ lib, pkgs, ... }:

{
  networking.hostName = "solo-workstation";
  time.timeZone = "America/Bahia";
  i18n.defaultLocale = "en_US.UTF-8";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "klarkc" ];
  networking.firewall.enable = true;

  services.tailscale.enable = true;
  # Expose RDP ONLY on the overlay interface; do not open GCP public port 3389.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3389 ];
  services.xrdp = {
    enable = true;
    openFirewall = false;
    defaultWindowManager = ''
      if [ -x "$HOME/.local/bin/xmonad-session" ] &&
         command -v xmonad >/dev/null 2>&1; then
        exec "$HOME/.local/bin/xmonad-session"
      fi
      exec ${pkgs.xfce.xfce4-session}/bin/xfce4-session
    '';
  };

  services.xserver = {
    enable = true;
    xkb.layout = "br";
    windowManager.xmonad.enable = true;
    desktopManager.xfce.enable = true;
  };
  services.displayManager.defaultSession = "xfce";

  users.users.klarkc = {
    isNormalUser = true;
    home = "/home/klarkc";
    createHome = true;
    shell = pkgs.bashInteractive;
    extraGroups = [ "wheel" ];
    # Do not expose RDP login until password is set via authenticated SSH.
    initialHashedPassword = "!";
  };

  security.sudo.wheelNeedsPassword = true;
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  environment.systemPackages = with pkgs; [
    git curl wget openssh tmux direnv bashInteractive
    xterm alacritty xfce.xfce4-terminal
    xorg.xauth xorg.xsetroot xorg.xmodmap
    xclip dbus dunst
    nix-output-monitor
    gnumake gcc
    tailscale
    google-cloud-sdk
  ];

  # The GCE base image uses Google OS Login and its standard guest agent.
  # No public key, password, or customer source code is baked into the image.
  system.stateVersion = "26.05";
}
